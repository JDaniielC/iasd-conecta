-- Horário/local de encontro deixam de ser obrigatórios no Grupo — quem tem
-- data/hora/local concretos é a Ação (o Grupo é só o ministério/time em si).
alter table public.grupos
  alter column horario drop not null,
  alter column local drop not null;
