"""Export the homepage's four recorded metrics from a verified historical bundle.

Usage: python website/scripts/export-history-overview.py PATH_TO_BUNDLE
No workloads are executed. Public output excludes local paths and process logs.
"""
import hashlib
import json
from pathlib import Path
import statistics
import sys

bundle = Path(sys.argv[1]).resolve()
public = Path(__file__).resolve().parents[1] / 'src/public/examples/bibliography'
integrity = json.loads((bundle / 'integrity.json').read_text(encoding='utf-8'))
for record in integrity['files']:
    source = (bundle / record['path']).resolve()
    if not source.is_relative_to(bundle):
        raise ValueError('Bundle file escapes its directory')
    raw = source.read_bytes()
    assert len(raw) == record['bytes']
    assert hashlib.sha256(raw).hexdigest() == record['sha256']

existing = json.loads((public / 'history/export-time.json').read_text(encoding='utf-8'))
manifest_hash = hashlib.sha256((bundle / 'manifest.json').read_bytes()).hexdigest()
assert manifest_hash == existing['input_manifest_sha256'], 'Not the published historical run'
versions = [row['version'] for row in existing['plot']['data']]
assert len(versions) == 9
observations = [json.loads(line) for line in
                (bundle / 'observations.jsonl').read_text(encoding='utf-8').splitlines()]
specs = [('time', 'julia.wall.time', 'ns'), ('gc', 'julia.gc.time', 'ns'),
         ('memory', 'julia.alloc.bytes', 'By'), ('allocations', 'julia.alloc.count', '1')]
metrics = []
for name, metric, unit in specs:
    rows = []
    for version in versions:
        selected = [row for row in observations if row['metric'] == metric
                    and row['attributes'].get('package') == 'Bibliography'
                    and row['attributes'].get('workload') == 'export_bibtex'
                    and row['attributes'].get('version') == version]
        assert len(selected) == 100 and all(row['unit'] == unit for row in selected)
        values = [row['value'] for row in selected]
        rows.append(dict(version=version, median=statistics.median(values),
                         minimum=min(values), maximum=max(values), samples=len(values)))
    metrics.append(dict(id=name, metric=metric, unit=unit, rows=rows))
assert [row['median'] for row in metrics[0]['rows']] == [row['value'] for row in existing['plot']['data']]
record = {key: existing[key] for key in
          ('run_id', 'runtime', 'os', 'sources', 'correctness', 'performance')}
record.update(versions=versions, metrics=metrics, input_manifest_sha256=manifest_hash,
              input_observations_sha256=hashlib.sha256((bundle / 'observations.jsonl').read_bytes()).hexdigest())
(public / 'history/overview.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
print('Exported four metrics, nine versions, 100 samples per metric/version.')
