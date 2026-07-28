(function initParkiMedicationEvents(root, factory) {
  const medicationEvents = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = medicationEvents;
  if (root) root.ParkiMedicationEvents = medicationEvents;
})(typeof window !== 'undefined' ? window : globalThis, function createParkiMedicationEvents() {
  const MEDICATION_CODES = {
    '레보도파': 'LEVODOPA',
    '시네메트': 'SINEMET',
    '마도파': 'MADOPAR',
    '미라펙스': 'MIRAPEX',
    '리큅': 'REQUIP',
    '기타': 'OTHER',
  };

  function requiredText(value, label) {
    if (typeof value !== 'string' || !value.trim()) throw new Error(`${label} is required`);
    return value.trim();
  }

  function validIso(value, label) {
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) throw new Error(`${label} must be a valid date`);
    return parsed.toISOString();
  }

  function finiteDose(value) {
    if (value === null || value === undefined || value === '') return null;
    const parsed = Number(value);
    return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
  }

  function eventIdFor(log) {
    return requiredText(log?.event_id || log?.id, 'event_id');
  }

  function buildMedicationStatementRow(log, identity) {
    const eventId = eventIdFor(log);
    const medication = requiredText(log?.medication, 'medication');
    const personId = requiredText(identity?.personId, 'person_id');
    const organizationId = requiredText(identity?.organizationId, 'organization_id');
    const takenAt = validIso(log?.taken_at, 'taken_at');
    const doseMg = finiteDose(log?.dose_mg);

    return {
      fhir_id: `parkicheck-medication-${eventId}`,
      status: 'completed',
      medication_code: MEDICATION_CODES[medication] || 'OTHER',
      medication_display: medication,
      medication_code_system: 'urn:parkicheck:patient-reported',
      subject_person_id: personId,
      organization_id: organizationId,
      effective_start: takenAt,
      date_asserted: new Date().toISOString(),
      dosage: {
        dose_mg: doseMg,
        unit: doseMg === null ? null : 'mg',
        event_type: 'patient_reported_dose',
        app_source: 'parkicheck',
      },
      note: 'Patient-reported medication dose event from ParkiCheck',
      information_source_type: 'patient',
      information_source_person_id: personId,
      created_by: personId,
    };
  }

  function parseMedicationStatementRow(row) {
    const prefix = 'parkicheck-medication-';
    const fhirId = requiredText(row?.fhir_id, 'fhir_id');
    if (!fhirId.startsWith(prefix)) throw new Error('not a ParkiCheck medication event');
    const eventId = fhirId.slice(prefix.length);
    return {
      id: eventId,
      event_id: eventId,
      server_id: row?.id || null,
      taken_at: validIso(row?.effective_start, 'effective_start'),
      medication: requiredText(row?.medication_display || row?.medication_code, 'medication'),
      dose_mg: finiteDose(row?.dosage?.dose_mg ?? row?.dosage?.dose?.value),
      sync_state: 'synced',
      source: 'supabase',
    };
  }

  function logKey(log) {
    const eventId = log?.event_id || log?.id;
    if (eventId !== null && eventId !== undefined && String(eventId).trim()) {
      return `event:${String(eventId).trim()}`;
    }
    return [log?.taken_at || '', log?.medication || '', log?.dose_mg ?? ''].join('|');
  }

  function mergeMedicationLogs(localLogs = [], serverLogs = []) {
    const merged = new Map();
    for (const log of localLogs) merged.set(logKey(log), log);
    for (const log of serverLogs) merged.set(logKey(log), log);
    return [...merged.values()].sort((a, b) => new Date(a.taken_at) - new Date(b.taken_at));
  }

  return {
    buildMedicationStatementRow,
    parseMedicationStatementRow,
    mergeMedicationLogs,
  };
});
