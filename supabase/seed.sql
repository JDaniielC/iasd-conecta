-- Dados de desenvolvimento/teste para a feature 001 (cadastro-usuario).
-- Igrejas: lista real do Distrito de Vitória de Santo Antão. Grupos padrão
-- (trigger `criar_grupos_padrao_igreja`, ver migration
-- 20260727100100_grupos_padrao_igreja.sql) não nascem aqui — o seed roda sem
-- usuário autenticado (auth.uid() nulo), então o trigger não tem dono pra
-- atribuir. Eles aparecem sozinhos quando um Administrador cadastra uma
-- Igreja pela UI (fluxo real). Lista de palavras bloqueadas é um conjunto
-- mínimo representativo para exercitar a moderação de nome.

insert into public.igrejas (nome) values
  ('Alto José Leal'),
  ('Pirituba'),
  ('Amparo'),
  ('Pombos'),
  ('Central'),
  ('Luiz Gonzaga'),
  ('Pedreira'),
  ('Vale Verde'),
  ('Mário Bezerra'),
  ('São Gustavo'),
  ('Maués'),
  ('Lagoa Redonda'),
  ('Apoti'),
  ('Cajueiro'),
  ('Boa Vista')
on conflict (nome) do nothing;

insert into public.palavras_bloqueadas (palavra) values
  ('idiota'),
  ('burro'),
  ('estupido'),
  ('imbecil'),
  ('babaca')
on conflict (palavra) do nothing;

-- Feature 002: categorias de Grupo (departamentos oficiais da IASD),
-- ver CATEGORIAS-DE-ACAO.md — lista de sugestão, não obrigatória (FR-004).
insert into public.categorias_grupo (nome) values
  ('Desbravadores'),
  ('Aventureiros'),
  ('Ministério do Adolescente'),
  ('Ministério Jovem'),
  ('Ministério da Música'),
  ('Ministério da Mulher'),
  ('Ministério do Homem'),
  ('Ministério da Família / Casais'),
  ('Ministério da Criança'),
  ('Escola Sabatina'),
  ('Ação Solidária Adventista (ASA)'),
  ('Ministério Pessoal / Evangelismo'),
  ('Comunicação'),
  ('Recepção'),
  ('Mordomia Cristã'),
  ('Publicações'),
  ('Saúde'),
  ('Serviço Voluntário Adventista'),
  ('Outros')
on conflict (nome) do nothing;

-- =====================================================================
-- Feature 013 — endereço da drenagem, SÓ no ambiente local
-- =====================================================================
-- Isto mora no seed, e não numa migration, de propósito: `supabase db reset`
-- roda o seed, e produção **nunca** roda. A migration que semeava este valor
-- deixava produção apontando para o Docker de quem desenvolve, e a fila de
-- remoção não drenava nunca — em silêncio. Ver
-- 20260810140000_drenagem_exige_configuracao.sql.
--
-- Em produção, este mesmo insert é feito uma vez, à mão, com o endereço real.
-- A instrução está em INFRA-PRODUCAO.md.
insert into public.configuracao_drenagem (url_funcao)
values ('http://host.docker.internal:54321/functions/v1/drenar-capas')
on conflict (id) do update set url_funcao = excluded.url_funcao;
