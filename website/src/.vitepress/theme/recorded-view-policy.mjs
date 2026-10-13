// A release axis is meaningful only when actual observations cover two targets.
export function recordedVersions(model) {
  const rows = model?.data ?? [];
  const identities = rows.map(row => row.version).filter(value => typeof value === 'string');
  if (identities.length) return [...new Set(identities)];
  const selected = model?.options?.selected_version;
  return typeof selected === 'string' ? [selected] : [];
}

export function isVersionComparison(model) {
  return recordedVersions(model).length >= 2;
}

export function isLatestDiagnostic(model) {
  return recordedVersions(model).length === 1 &&
    ['cpu_flamegraph', 'wall_flamegraph', 'allocation_flamegraph',
      'allocation_pie', 'allocation_lines'].includes(model?.kind);
}
