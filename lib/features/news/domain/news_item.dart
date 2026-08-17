/// Uma Novidade: o que mudou no app, contado para quem usa.
///
/// Dois campos, e é de propósito — sem `id`, sem `title`, sem `category`, sem
/// `version`. Cada campo a mais seria uma decisão de produto que ninguém pediu,
/// e o motivo de cada ausência está em `specs/022-novidades/data-model.md`.
///
/// O texto se escreve segundo `CRITERIO-DE-NOVIDADE.md`, na raiz do
/// repositório. A regra curta: vira Novidade o que **a pessoa percebe**, e se
/// escreve no que muda **para ela**.
class NewsItem {
  const NewsItem({required this.date, required this.text});

  /// Quando a mudança chegou às pessoas. É por ela que a lista ordena e que o
  /// aviso decide se há algo novo.
  final DateTime date;

  final String text;
}

/// A partir de quando as Novidades aparecem.
///
/// **Filtro de exibição, não regra de escrita**: uma Novidade pode ser escrita
/// com data anterior a esta e simplesmente não aparece.
///
/// Era 6 de outubro de 2026, o lançamento para o distrito. Passou a ser a data
/// do primeiro commit do projeto porque o dono do app pediu que as mudanças já
/// feitas fossem escritas e ficassem visíveis — e todas elas são de agosto,
/// antes do lançamento. Com o marco em outubro, a lista aparecia vazia.
///
/// **6 de outubro de 2026 continua sendo a data de lançamento ao distrito**;
/// ela só deixou de ser o filtro. Voltar atrás é trocar esta linha.
final launchDate = DateTime.utc(2026, 7, 23);

/// Todas as Novidades já escritas, da mais antiga para a mais nova.
///
/// Escritas à mão, uma a uma, segundo `CRITERIO-DE-NOVIDADE.md` — nunca
/// geradas do histórico de código. A regra curta: vira Novidade o que **a
/// pessoa percebe**, e se escreve no que muda **para ela**.
///
/// `final` e não `const` porque `DateTime` não tem construtor constante.
final allNews = <NewsItem>[
  NewsItem(
    date: DateTime.utc(2026, 8, 6),
    text:
        'Agora você pode apagar sua conta sozinho, pelo app. Apagamos seu '
        'nome, Apelido, telefone, igreja de origem, gênero e idade, e você sai '
        'dos Grupos/Ministérios de que participa e das Ações que ainda vão '
        'acontecer.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 9),
    text:
        'O app abre numa página que explica o que ele é: o que é um '
        'Grupo/Ministério, o que é uma Ação, e como participar.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 9),
    text:
        'A Ação aparece com o nome dela, e não com o nome de quem a criou. '
        'A lista de confirmados vem numerada, e a listagem mostra quantas '
        'pessoas já confirmaram presença em cada Ação.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 9),
    text:
        'Ação que já aconteceu sai da lista. E depois que ela termina, '
        'ninguém mais entra no lugar de quem desistiu — antes, alguém podia '
        'ser chamado para um encontro que já tinha passado.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 9),
    text:
        'Em quem você votou agora só você vê. Antes, qualquer pessoa '
        'conseguia consultar. Quando a Rodada de votação fecha, o app conta os '
        'votos e anuncia a Ação vencedora, sem mostrar a ninguém quem votou '
        'em quê.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 9),
    text:
        'Quem se declara Líder ou Diretor de um Ministério e não é '
        'confirmado não aparece mais para ninguém. Enquanto sua declaração '
        'espera resposta, só você e o Administrador do distrito a enxergam.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 9),
    text:
        'Você já pode ver e corrigir seus dados sozinho, em Meu Perfil: '
        'nome, Apelido, igreja de origem e telefone. Antes era preciso '
        'escrever para a gente e esperar resposta.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 10),
    text:
        'O Dono de um Grupo/Ministério pode arquivá-lo quando ele deixa de '
        'existir. Antes de confirmar, o app mostra quantas Ações marcadas '
        'serão canceladas e quantas pessoas já tinham confirmado presença '
        'nelas.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 10),
    text:
        'Cadastro de criança com menos de 13 anos passa a pedir o nome de um '
        'responsável, um contato dele e a autorização dele. É o que a lei '
        'exige para dado de criança.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 10),
    text:
        'Seu Grupo/Ministério e suas Ações podem ter uma imagem de capa. '
        'Quem é Dono do Grupo, ou criou a Ação, escolhe a imagem — e ela fica '
        'visível para qualquer pessoa que vê o Grupo, inclusive quem não tem '
        'cadastro. Por isso o app pede imagem ilustrativa, como logo, arte ou '
        'foto do local: não envie foto de pessoa, e nunca de criança ou '
        'adolescente.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 10),
    text:
        'Se você vir uma imagem que não deveria estar ali, pode avisar pelo '
        'próprio app, sem precisar de cadastro e sem dizer quem você é. O '
        'Administrador do distrito recebe o aviso e tira a imagem do ar.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 10),
    text:
        'Imagem tirada do ar pode continuar aparecendo por até um minuto '
        'para quem já tinha guardado o endereço dela. Passado esse minuto, o '
        'endereço deixa de responder para todo mundo.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 13),
    text:
        'Uma Ação de Grupo/Ministério pode ser fechada a quem participa do '
        'Grupo. Quem criou a Ação e o Dono do Grupo decidem isso; fechada, ela '
        'some da lista para quem é de fora. Ação avulsa, que não pertence a '
        'nenhum Grupo, continua aberta a todo mundo — não há a quem fechá-la.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 13),
    text:
        'Você já pode chamar alguém para uma Ação por dentro do app. Quem '
        'aparece para você chamar são as pessoas dos Grupos/Ministérios de que '
        'você participa. O convite não guarda vaga: quem aceitar ainda '
        'confirma presença, e entra na lista ou na fila pela regra de sempre.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 13),
    text:
        'O app avisa você por dentro dele quando algo é dirigido a você — um '
        'convite que chegou, e a resposta de quem você convidou. O número de '
        'avisos não lidos fica na barra do app, e a lista em Notificações. '
        'Aviso de Ação cancelada ou já encerrada não fica pendurado lá.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 13),
    text:
        'Grupo/Ministério e Ação passam a mostrar o que mudou: horário e '
        'local alterados, Ação criada ou cancelada, quem entrou ou saiu, quem '
        'confirmou ou desistiu. Só vale daqui para a frente — o que aconteceu '
        'antes não foi guardado e não dá para reconstruir.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 13),
    text:
        'A lista de Ações ganhou um destaque no topo: as Ações abertas a '
        'todo o distrito, e as Ações novas dos Grupos/Ministérios de que você '
        'participa. Você pode fechar cada uma; elas voltam a aparecer na '
        'próxima vez que abrir o app, enquanto ainda forem novidade para você.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 16),
    text:
        'Grupo/Ministério e Ação passam a ter conversa dentro do app, para '
        'combinar quem leva o quê e a que horas. No Grupo, conversa quem '
        'participa. Na Ação, quem confirmou presença ou está na fila, mais '
        'quem criou a Ação e o Dono do Grupo dela.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 16),
    text:
        'A conversa é só para quem tem 18 anos ou mais. Não é decisão de '
        'ninguém sobre você: nela as pessoas escrevem texto livre, e não há '
        'como acompanhar isso a tempo para menores de idade. Todo o resto '
        'continua igual — participar, votar, propor e confirmar presença.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 16),
    text:
        'A conversa de uma Ação é apagada 30 dias depois da data dela. A '
        'conversa de um Grupo/Ministério fica — é dele, e não de um encontro '
        'que passou.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 16),
    text:
        'Se alguém escrever algo que não deveria, você pode denunciar a '
        'mensagem pela própria conversa, contando o que há de errado. Quem '
        'cuida do espaço — o Dono do Grupo, quem criou a Ação, ou o '
        'Administrador do distrito — decide. Mensagem retirada some para todo '
        'mundo, fica só a marca de que havia algo ali, e o texto não é '
        'guardado em lugar nenhum.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 16),
    text:
        'Excluir sua conta passa a apagar também o texto das mensagens que '
        'você escreveu. Fica a marca de que houve mensagem ali, para a '
        'conversa continuar fazendo sentido para quem ficou. Mensagem escrita '
        'por outra pessoa, mesmo citando você, não é apagada por aí — o '
        'caminho para ela é a denúncia.',
  ),
  // Change `fechar-superficie-anon`. Correção de segurança COM efeito sobre o
  // que os outros enxergam da pessoa — a exceção que o CRITERIO-DE-NOVIDADE.md
  // manda escrever, no molde do exemplo da Liderança.
  NewsItem(
    date: DateTime.utc(2026, 8, 16),
    text:
        'De quais Grupos e Ministérios você participa deixou de ser visível '
        'para quem não entrou no app. Antes, essa lista podia ser consultada '
        'de fora, sem login. Dentro do app nada muda: quem já via, continua '
        'vendo.',
  ),
  // Change `filtro-e-intervalo-de-mensagem`. DOIS itens porque são duas ideias
  // — a regra 3 do critério. As duas são recusa que a pessoa leva na cara, e a
  // segunda existe também porque o direito de revisão de uma decisão
  // automatizada só se exerce sobre regra que a pessoa sabe que existe
  // (REVISAO-JURIDICA.md § 4-D).
  NewsItem(
    date: DateTime.utc(2026, 8, 17),
    text:
        'Algumas palavras não são aceitas nas conversas nem no texto de uma '
        'denúncia. Se você usar uma delas, a mensagem não é enviada e o app '
        'diz qual foi a palavra, para você trocar e mandar de novo. O que '
        'você escreveu não se perde.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 17),
    text:
        'Há um ritmo máximo para escrever numa conversa: uma mensagem a cada '
        'poucos segundos, e um limite por conversa a cada poucos minutos. '
        'Serve para ninguém encher o chat de todo mundo. Quando o limite '
        'pega, o app diz quanto falta para você poder enviar, e o texto '
        'continua no campo.',
  ),
  NewsItem(
    date: DateTime.utc(2026, 8, 17),
    text:
        'Quem cuida do espaço — o Dono do Grupo, quem criou a Ação ou o '
        'Administrador do distrito — pode fixar uma mensagem no alto da '
        'conversa, até 3 por conversa. O que fica fixado numa conversa de '
        'Ação não é apagado no prazo de 30 dias, e é o ponto: o endereço e a '
        'lista do que cada um leva costumam ser justamente o que precisa '
        'sobreviver ao encontro. Se a mensagem é sua, você pode desfixá-la '
        'pela própria conversa, e a partir daí ela volta a contar o prazo '
        'normal. Isso muda o que dizia a Novidade anterior sobre os 30 dias: '
        'o prazo continua, com essa exceção. A Política de Privacidade '
        'explica tudo, inclusive o que fazer se você já não alcança a '
        'conversa.',
  ),
];

/// O que de fato aparece na tela: descarta o que é anterior ao lançamento e
/// ordena da data mais recente para a mais antiga.
///
/// Função pura, recebendo a lista por parâmetro, para poder ser testada com
/// listas montadas à mão em vez de depender do conteúdo real.
List<NewsItem> visibleNews(List<NewsItem> items) {
  final visible =
      items.where((item) => !item.date.isBefore(launchDate)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  return visible;
}
