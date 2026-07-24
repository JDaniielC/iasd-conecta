-- Consentimento LGPD destacado para "Igreja de origem" (dado sensível,
-- LGPD art. 5º II / art. 11 I). Ver ticket .tickets/IASD-01.md.
-- origem: .achados/20260724-devops-iasd.md#A-1,
--         .achados/20260724-direito-digital-iasd.md#A-2

alter table public.perfis
  add column consentimento_lgpd_igreja_aceito_em timestamptz;

alter table public.perfis
  add constraint consentimento_igreja_destacado
  check (igreja_id is null or consentimento_lgpd_igreja_aceito_em is not null);
