create policy "medication_statements_patient_reported_insert"
on public.medication_statements
for insert
to authenticated
with check (
  subject_person_id = (select public.get_my_person_id())
  and created_by = (select public.get_my_person_id())
  and information_source_person_id = (select public.get_my_person_id())
  and information_source_type = 'patient'
  and medication_code_system = 'urn:parkicheck:patient-reported'
  and status = 'completed'
  and exists (
    select 1
    from public.organization_members om
    where om.person_id = (select public.get_my_person_id())
      and om.organization_id = medication_statements.organization_id
      and om.status = 'active'
      and om.deleted_at is null
  )
);
