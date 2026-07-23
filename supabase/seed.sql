-- Dados de desenvolvimento/teste para a feature 001 (cadastro-usuario).
-- Lista de Igrejas é ilustrativa — gestão real é feature futura do
-- Administrador do distrito (ver CONTEXT.md). Lista de palavras bloqueadas é
-- um conjunto mínimo representativo para exercitar a moderação de nome.

insert into public.igrejas (nome) values
  ('Igreja Central de Vitória de Santo Antão'),
  ('Igreja Adventista do Bairro Fátima'),
  ('Igreja Adventista do Bairro Cocié'),
  ('Igreja Adventista do Bairro Cana Brava'),
  ('Igreja Adventista do Bairro Bonança'),
  ('Igreja Adventista do Bairro Toró'),
  ('Igreja Adventista do Bairro Sítio Novo'),
  ('Igreja Adventista de Camutanga'),
  ('Igreja Adventista de Chã de Alegria'),
  ('Igreja Adventista de Chã Grande'),
  ('Igreja Adventista de Cortês'),
  ('Igreja Adventista de Glória do Goitá'),
  ('Igreja Adventista de Pombos'),
  ('Igreja Adventista de Primavera'),
  ('Igreja Adventista de São Lourenço da Mata'),
  ('Igreja Adventista de Vitória de Santo Antão - Sede')
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
  ('Serviço Voluntário Adventista')
on conflict (nome) do nothing;
