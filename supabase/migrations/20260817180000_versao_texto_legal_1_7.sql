-- Change mensagem-fixada — a versão 1.7 do texto legal.
--
-- Gêmea da constante `LegalMetadata.version`, pelo mesmo motivo da 1.6
-- (20260816170000): o texto está compilado no binário e a versão é metadado
-- dele. `test/integration/versao_texto_legal_registro_test.dart` falha se
-- divergirem, e a divergência NÃO daria erro em produção — gravaria em cada
-- cadastro novo uma versão diferente da que a pessoa leu na tela.
--
-- MIGRATION SEPARADA da 20260817160000, e é a mesma decisão da 1.6: aquela é o
-- mecanismo e pode subir sozinha — sem ninguém fixando nada, o comportamento é
-- idêntico ao de antes. Esta é a PUBLICAÇÃO do texto novo, e só vale depois de
-- os dois documentos estarem corrigidos.
--
-- POR QUE SOBE. Esta change não acrescenta dado pessoal novo além de quem fixou
-- e quando. O que ela muda é mais forte: a Política dizia, SEM RESSALVA, que as
-- mensagens da Ação são apagadas 30 dias depois do encontro, e desde
-- 20260817160000 o `delete` do expurgo tem `and m.fixada_em is null`. Manter a
-- 1.6 carimbaria consentimento sob um texto que a migration anterior acabou de
-- tornar falso — o mesmo caso que fez a 1.6 subir.
--
-- Prazo declarado é a informação que a titular usa para decidir o que escreve.
-- E a exceção é acionável por OUTRA pessoa sobre texto dela: quem cuida do
-- espaço fixa, e a mensagem para de expirar. O contrapeso existe — o autor
-- sempre desfixa a própria mensagem, mesmo sem autoridade no espaço — e só
-- serve a quem sabe que ele existe. Ver REVISAO-JURIDICA.md.
insert into public.versoes_texto_legal (versao, vigente_desde)
values ('1.7', timestamptz '2026-08-17 00:00:00-03')
on conflict (versao) do nothing;
