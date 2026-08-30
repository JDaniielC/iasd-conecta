-- Change alcance-do-titular-sobre-texto-proprio — a versão 1.8 do texto legal.
--
-- Gêmea da constante `LegalMetadata.version`, pelo mesmo motivo da 1.6 e da
-- 1.7: o texto está compilado no binário e a versão é metadado dele.
-- `test/integration/versao_texto_legal_registro_test.dart` falha se
-- divergirem, e a divergência NÃO daria erro em produção — gravaria em cada
-- cadastro novo uma versão diferente da que a pessoa leu na tela.
--
-- MIGRATION SEPARADA das que criam `desfixar_minha_mensagem` e
-- `minhas_mensagens_fixadas`, e é a mesma decisão da 1.6 e da 1.7: aquelas são
-- o mecanismo e podem subir sozinhas — sem ninguém usando o caminho novo, o
-- comportamento antigo continua de pé. Esta é a PUBLICAÇÃO do texto novo, e
-- só vale depois de a tela em Meu Perfil e o bullet da Política estarem
-- corrigidos.
--
-- POR QUE SOBE. Esta change não acrescenta dado pessoal novo: as duas funções
-- só alcançam `fixada_em`/`fixada_por` de mensagem que o próprio autor
-- escreveu, e a leitura de "Meu Perfil" devolve texto da própria pessoa. O que
-- muda é o contrapeso que sustentou a subida para 1.7 — "o autor sempre
-- desfixa a própria mensagem, mesmo sem autoridade no espaço" — que hoje passa
-- a se cumprir também fora da conversa. A Política 1.7 declarava esse limite
-- e mandava escrever para o e-mail de contato; manter esse texto depois de o
-- botão existir seria a mesma classe de defeito que a própria 1.7 consertou
-- (prometer um aviso quando o certo é o caminho). Ver REVISAO-JURIDICA.md
-- § 4-E e PENDENCIAS.md 2.28.
insert into public.versoes_texto_legal (versao, vigente_desde)
values ('1.8', timestamptz '2026-08-30 00:00:00-03')
on conflict (versao) do nothing;
