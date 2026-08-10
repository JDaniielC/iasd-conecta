// Feature 013 — drena a fila de capas a remover.
//
// POR QUE ISTO É UMA EDGE FUNCTION, E NÃO SQL
// Apagar a linha em storage.objects por SQL não apaga o binário — a
// documentação do fornecedor é explícita: "Deleting objects via a SQL query
// will not remove the object from the bucket and will result in the object
// being orphaned." Remover de verdade exige chamar a API de armazenamento.
//
// POR QUE AQUI, E NÃO NO GATILHO
// Chamar a API de dentro do gatilho poria rede dentro da transação que apaga a
// linha — e uma dessas transações é excluir_minha_conta. Uma falha de rede
// abortaria a exclusão de conta. O gatilho só enfileira; esta função drena,
// fora de qualquer transação de usuário.
//
// POR QUE NÃO HÁ SEGREDO GUARDADO EM LUGAR NENHUM
// SUPABASE_SERVICE_ROLE_KEY é injetada pelo próprio Supabase no ambiente da
// função. Ela nunca é escrita no banco, no repositório, nem em arquivo de
// configuração — que era o desenho anterior, com Vault, e é pior: chave de
// serviço ignora RLS, e guardá-la cria mais um segredo para vazar e rotacionar.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const BUCKET = 'fotos-capa';
const LOTE = 100;

Deno.serve(async () => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // `tentativas` vem no select porque o caminho de falha precisa dela. A
  // primeira versão pedia só `caminho` e, na falha, escrevia
  // `pendentes[0]?.tentativas ?? 0` — sempre zero, e o valor da primeira linha
  // aplicado ao lote inteiro. A coluna existe para separar "falhou uma vez, foi
  // rede" de "falha desde sempre, tem algo errado com este arquivo", e
  // respondia zero para os dois casos.
  const { data: pendentes, error: erroLeitura } = await supabase
    .from('capas_a_remover')
    .select('caminho, tentativas')
    .is('removido_em', null)
    .order('enfileirado_em')
    .limit(LOTE);

  if (erroLeitura) {
    return Response.json({ erro: erroLeitura.message }, { status: 500 });
  }
  if (!pendentes || pendentes.length === 0) {
    return Response.json({ drenados: 0, pendentes: 0 });
  }

  const caminhos = pendentes.map((linha) => linha.caminho as string);
  const { data: removidos, error: erroRemocao } = await supabase.storage
    .from(BUCKET)
    .remove(caminhos);

  // ===================================================================
  // NÃO BASTA "NÃO DEU ERRO" — TEM DE VOLTAR NA LISTA DOS REMOVIDOS
  // ===================================================================
  // Medido em 2026-08-10: com um bucket que NÃO EXISTE, `remove()` devolve
  // `error` nulo. A versão anterior tratava isso como sucesso e carimbava
  // `removido_em` — a linha saía da fila como drenada, o arquivo continuava
  // público, `tentativas` ficava 0 e `ultimo_erro` nulo. A consulta de fila
  // parada mostraria ZERO.
  //
  // Ou seja: um nome de bucket errado transformava a fila inteira em teatro,
  // em silêncio. É o "sumiu e ninguém sabe" que este desenho existe para
  // impedir, entrando pela porta que ninguém trancou.
  //
  // Então a confirmação passa a ser positiva: só sai da fila o caminho que a
  // API devolve como removido. O que não voltar continua pendente, conta a
  // tentativa e guarda o motivo — visível na consulta de INFRA-PRODUCAO.md § 3.
  const confirmados = new Set(
    (removidos ?? []).map((objeto) => objeto.name as string),
  );
  const naoConfirmados = pendentes.filter(
    (linha) => !confirmados.has(linha.caminho as string),
  );

  // Uma atualização POR LINHA, e não um `.in()` com valor único: cada arquivo
  // tem a sua contagem, e é a diferença entre elas que denuncia o arquivo que
  // falha desde sempre no meio de falhas transitórias. São no máximo LOTE
  // requisições, e só quando algo deu errado.
  if (naoConfirmados.length > 0) {
    const motivo = erroRemocao?.message ??
      'A API não confirmou a remoção deste caminho. Bucket errado, ou o ' +
        'objeto já não existia.';
    await Promise.all(
      naoConfirmados.map((linha) =>
        supabase
          .from('capas_a_remover')
          .update({
            tentativas: ((linha.tentativas as number | null) ?? 0) + 1,
            ultimo_erro: motivo,
          })
          .eq('caminho', linha.caminho as string)
      ),
    );
  }

  // Só marca o que a API confirmou. Marcar antes, ou marcar o que ela não
  // confirmou, seria transformar uma falha em órfão permanente e invisível.
  if (confirmados.size > 0) {
    const { error: erroMarcacao } = await supabase
      .from('capas_a_remover')
      .update({ removido_em: new Date().toISOString(), ultimo_erro: null })
      .in('caminho', [...confirmados]);

    if (erroMarcacao) {
      return Response.json({ erro: erroMarcacao.message }, { status: 500 });
    }
  }

  if (erroRemocao) {
    return Response.json({ erro: erroRemocao.message }, { status: 500 });
  }

  return Response.json({
    drenados: confirmados.size,
    nao_confirmados: naoConfirmados.length,
  });
});
