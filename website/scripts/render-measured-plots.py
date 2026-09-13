"""Render documentation figures from public recorded data (no benchmark runs).

Install plot-requirements.txt, then run this file from any working directory.
SVGs keep text selectable and use linear, zero-based cost axes.
"""
import hashlib
import json
import os
from pathlib import Path

os.environ.setdefault('OPENBLAS_NUM_THREADS', '1')
os.environ.setdefault('OMP_NUM_THREADS', '1')
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

root = Path(__file__).resolve().parents[1] / 'src/public/examples/bibliography'
out = root / 'figures'
out.mkdir(exist_ok=True)
plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 12,
                     'svg.fonttype': 'none', 'svg.hashsalt': 'perfchecker-recorded-plots',
                     'axes.spines.top': False, 'axes.spines.right': False})
inputs = {}

def read(relative):
    raw = (root / relative).read_bytes()
    inputs[relative] = hashlib.sha256(raw).hexdigest()
    return json.loads(raw)

def save(fig, name):
    fig.savefig(out / (name + '.svg'), bbox_inches='tight', facecolor='white',
                metadata={'Date': None, 'Creator': 'PerfChecker recorded-data figure exporter'})
    plt.close(fig)

def decorate(ax, title, unit):
    ax.set_title(title, loc='left', fontweight='bold', pad=16)
    ax.set_ylabel(unit)
    ax.set_ylim(bottom=0)
    ax.grid(axis='y', color='#e2e8f0')
    ax.set_axisbelow(True)

for name, title, unit, scale in [
    ('export-time', 'Bibliography export · nine tagged versions', 'Median elapsed time (µs)', 1000),
    ('export-memory', 'Bibliography export · allocated bytes', 'Allocated bytes per export (B)', 1),
    ('import-time', 'Bibliography import · nine tagged versions', 'Median elapsed time (µs)', 1000),
]:
    rows = read('history/' + name + '.json')['plot']['data']
    assert len(rows) == 9 and all(row['samples'] == 100 for row in rows)
    fig, ax = plt.subplots(figsize=(10, 4.7), layout='constrained')
    ax.plot([r['version'] for r in rows], [r['value']/scale for r in rows],
            marker='o', linewidth=2, color='#087e8b')
    decorate(ax, title, unit)
    ax.set_xlabel('Tagged version · equal spacing')
    ax.tick_params(axis='x', rotation=25)
    save(fig, 'history-' + name.removeprefix('export-'))

rows = read('history/export-samples.json')['plot']['data']
versions = list(dict.fromkeys(r['version'] for r in rows))
assert len(rows) == 900 and len(versions) == 9
fig, ax = plt.subplots(figsize=(10, 5), layout='constrained')
for x, version in enumerate(versions):
    ys = [r['value']/1000 for r in rows if r['version'] == version]
    # Deterministic horizontal displacement only prevents points hiding each other.
    xs = x + np.linspace(-.22, .22, len(ys))
    ax.scatter(xs, ys, alpha=.48, s=15, color='#087e8b')
    ax.plot([x-.3,x+.3],[np.median(ys)]*2, color='#182c46', linewidth=3)
ax.set_xticks(range(len(versions)), versions, rotation=25)
decorate(ax, 'Bibliography export · all 900 timing samples', 'Elapsed time per sample (µs)')
ax.set_xlabel('Tagged version · horizontal displacement separates points only')
save(fig, 'history-samples')

rows = read('history/export-delta.json')['plot']['data']
assert len(rows) == 8
fig, ax = plt.subplots(figsize=(10, 4.7), layout='constrained')
values = [r['relative_delta']*100 for r in rows]
ax.bar([r['candidate_version'] for r in rows], values,
       color=['#087e8b' if v < 0 else '#9a5b18' for v in values])
ax.axhline(0, color='#182c46', linewidth=1)
ax.set_title('Bibliography export · change from tag 0.1.0', loc='left', fontweight='bold', pad=16)
ax.set_ylabel('Change in median elapsed time (%)')
ax.set_xlabel('Candidate version · negative means less time')
ax.grid(axis='y', alpha=.2); ax.set_axisbelow(True)
save(fig, 'history-delta')

comparison = read('streaming-comparison.json')
series = {s['metric']: s for s in comparison['series']}
fig, axes = plt.subplots(1, 3, figsize=(12, 4.5), layout='constrained')
for ax, (metric, title, unit, scale) in zip(axes, [
    ('julia.alloc.bytes', 'Allocation activity', 'Bytes per export (B)', 1),
    ('julia.alloc.count', 'Allocation events', 'Events per export', 1),
    ('julia.wall.time', 'Elapsed time', 'Median time (µs)', 1000),
]):
    points = {p['version']: p for p in series[metric]['points']}
    values = [points[k]['median']/scale for k in ['before-streaming', 'after-streaming']]
    ax.bar(['Parent\n6a4cc90', 'Streaming\n575ec81'], values, color=['#526681', '#087e8b'], width=.62)
    decorate(ax, title, unit)
    ax.set_ylim(top=max(values)*1.28)
    for i, val in enumerate(values):
        ax.text(i, val+max(values)*.035, f'{val:,.2f}'.rstrip('0').rstrip('.'), ha='center')
fig.suptitle('One export change · fixed dependency revisions · 100 samples per revision', fontsize=14)
save(fig, 'streaming-comparison')

overview = read('history/overview.json')
for metric, title, unit, scale, color in [
    ('time', 'Elapsed time', 'Median per export (µs)', 1000, '#087e8b'),
    ('gc', 'Garbage collection', 'Median GC time (µs)', 1000, '#b46a22'),
    ('memory', 'Allocated memory', 'Bytes per export (B)', 1, '#7655ad'),
    ('allocations', 'Allocation count', 'Allocations per export', 1, '#3372b7'),
]:
    rows = next(item['rows'] for item in overview['metrics'] if item['id'] == metric)
    values = [row['median'] / scale for row in rows]
    fig, ax = plt.subplots(figsize=(5.5, 3.6), layout='constrained')
    ax.plot(range(len(rows)), values, color=color, linewidth=2.3,
            marker='o', markersize=5, clip_on=False)
    ax.fill_between(range(len(rows)), values, color=color, alpha=.07)
    decorate(ax, title, unit)
    ax.set_xticks(range(len(rows)), [row['version'] for row in rows], rotation=40)
    ax.tick_params(axis='both', labelsize=10)
    ax.set_xlim(-.2, len(rows)-.8)
    ax.set_xlabel('Bibliography tag', fontsize=10)
    if max(values) == 0:
        ax.set_ylim(0, 1)
        ax.set_yticks([0])
        ax.text(.5, .5, 'No GC time recorded\nin these 900 export samples',
                transform=ax.transAxes, ha='center', va='center', color='#705332', fontsize=11)
    else:
        ax.set_ylim(0, max(values)*1.17)
    save(fig, 'overview-' + metric)

normalized = read('history/normalized.json')['plot']
fig, ax = plt.subplots(figsize=(11, 5), layout='constrained')
versions = normalized['options']['versions']
for metric, label, color in [
    ('julia.wall.time', 'Elapsed time', '#087e8b'),
    ('julia.gc.time', 'GC time (all zero: unchanged)', '#b46a22'),
    ('julia.alloc.bytes', 'Allocated bytes', '#7655ad'),
    ('julia.alloc.count', 'Allocation count', '#3372b7'),
]:
    rows = {r['version']: r for r in normalized['data'] if r['metric'] == metric}
    values = [rows[v]['ratio'] if v in rows and rows[v]['ratio'] is not None else np.nan for v in versions]
    ax.plot(versions, values, marker='o', linewidth=2, color=color, label=label)
ax.axhline(1, color='#526681', linestyle='--', linewidth=1)
decorate(ax, 'Bibliography export · four measurements on one axis', 'Minimum per version / minimum across versions')
ax.set_xlabel('Version · the best value of each metric is 1')
ax.legend(ncols=2, frameon=False, fontsize=10)
save(fig, 'normalized')

(out / 'provenance.json').write_text(json.dumps({'inputs_sha256': inputs,
    'renderer': 'matplotlib', 'renderer_version': matplotlib.__version__,
    'sample_positions': 'deterministic horizontal displacement, not execution order',
    'figures': sorted(p.name for p in out.glob('*.svg'))}, indent=2)+'\n', encoding='utf-8')
print('Rendered measured figures; input SHA-256 digests saved in figures/provenance.json')
