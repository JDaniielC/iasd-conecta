-- Categoria "Outros" — sem ela, Grupo/Ação que não se encaixa nos
-- departamentos oficiais da IASD fica sem opção de Categoria pra selecionar
-- (campo obrigatório em criar_grupo_page.dart).
insert into public.categorias_grupo (nome) values
  ('Outros')
on conflict (nome) do nothing;
