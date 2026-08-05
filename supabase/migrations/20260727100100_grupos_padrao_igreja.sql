-- Toda Igreja nasce com os 6 ministérios mais comuns já como Grupo (ver
-- CATEGORIAS-DE-ACAO.md, seis primeiras seções). Dono provisório é quem
-- cadastrou a Igreja (sempre um Administrador do distrito, único jeito de
-- inserir em `igrejas` — ver policy `igrejas_insert_admin`); FR-011 de
-- grupos (`grupos_dono_deve_participar`) já cobre a transferência de posse
-- depois. `auth.uid()` nulo (seed/migration, sem sessão autenticada) faz o
-- trigger não fazer nada — sem dono não dá pra criar o Grupo (`dono_id not
-- null`).
create function public.criar_grupos_padrao_igreja()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  insert into public.grupos (nome, categoria, igreja_id, dono_id)
  select c.nome, c.nome, new.id, auth.uid()
  from public.categorias_grupo c
  where c.nome in (
    'Desbravadores',
    'Aventureiros',
    'Ministério do Adolescente',
    'Ministério Jovem',
    'Ministério da Música',
    'Ministério da Mulher'
  );

  return new;
end;
$$;

create trigger igrejas_criar_grupos_padrao
  after insert on public.igrejas
  for each row
  execute function public.criar_grupos_padrao_igreja();
