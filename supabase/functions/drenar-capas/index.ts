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

  const { data: pendentes, error: erroLeitura } = await supabase
    .from('capas_a_remover')
    .select('caminho')
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
  const { error: erroRemocao } = await supabase.storage
    .from(BUCKET)
    .remove(caminhos);

  if (erroRemocao) {
    // A linha fica na fila e será tentada de novo. Registrar o erro e contar a
    // tentativa é o que transforma "sumiu e ninguém sabe" em algo consultável.
    await supabase
      .from('capas_a_remover')
      .update({
        tentativas: (pendentes as { tentativas?: number }[])[0]?.tentativas ?? 0,
        ultimo_erro: erroRemocao.message,
      })
      .in('caminho', caminhos);
    return Response.json({ erro: erroRemocao.message }, { status: 500 });
  }

  // Só marca depois que a API confirmou. Marcar antes seria transformar uma
  // falha de rede em órfão permanente e invisível.
  const { error: erroMarcacao } = await supabase
    .from('capas_a_remover')
    .update({ removido_em: new Date().toISOString(), ultimo_erro: null })
    .in('caminho', caminhos);

  if (erroMarcacao) {
    return Response.json({ erro: erroMarcacao.message }, { status: 500 });
  }

  return Response.json({ drenados: caminhos.length });
});
