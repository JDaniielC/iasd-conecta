# Rede Social do Distrito Vitória de Santo Antão

Rede social para os membros ativos da Igreja Adventista do Sétimo Dia do distrito de Vitória de Santo Antão (15+ igrejas) descobrirem e se conectarem através de atividades (Grupos e Ações).

## Language

**Visitante**:
Qualquer pessoa sem cadastro. Pode ver Grupos e Ações livremente, mas não participar, votar ou criar nada — isso exige virar Usuário.

**Usuário**:
Pessoa cadastrada no app (cadastro simples, apenas para identificação). Dados: nome (moderado contra palavrões; se menor de idade, exibido como Apelido em vez do nome real), Igreja de origem (seletor entre as igrejas do distrito; pode ficar em branco — nem todo usuário é vinculado a uma igreja), telefone (opcional), gênero, idade (nunca exibida a outros usuários, reservada para uso futuro) e consentimento LGPD de uso desses dados. Todo Usuário começa como Perfil; só precisa virar Conta se for declarar-se Líder/Diretor.

**Perfil**:
Nível padrão de cadastro de um Usuário: sem credencial de login obrigatória (sem e-mail/senha exigidos). Cobre tudo que um Usuário comum faz — participar de Grupo, votar, propor Ação candidata, confirmar presença em Ação. Vive só no aparelho: se o Usuário reinstalar o app ou trocar de aparelho sem antes virar Conta, o Perfil se perde. Suficiente pra 100% das ações desta feature, exceto declarar-se Líder/Diretor.
_Avoid_: Conta (não são sinônimos — Perfil é o padrão sem credencial, Conta é o upgrade com credencial)

**Conta**:
Upgrade opcional do Perfil: vincula uma credencial de login real (o que o Supabase oferecer — e-mail/senha, telefone, etc., a critério de implementação), tornando a identificação recuperável entre aparelhos. Só é exigida quando o Usuário quer se declarar Líder/Diretor de um Ministério — porque essa identificação é pública (visível até pra Visitante) e não pode se perder com reinstalação do app. Fora esse caso, Conta é sempre opcional.
_Avoid_: Perfil, cadastro completo

**Apelido**:
Nome de exibição alternativo, sem informação identificável, usado no lugar do nome real quando o Usuário é menor de idade.

**Categoria de Grupo**:
Classificação de um Grupo por tipo de ministério/departamento da IASD (ex: Desbravadores, Ministério Jovem, Ministério da Música). Alimenta as sugestões de Ação oferecidas na hora de criar. Lista de referência em [CATEGORIAS-DE-ACAO.md](./CATEGORIAS-DE-ACAO.md).
_Avoid_: Departamento, Tipo de grupo

**Ação sugerida**:
Nome de Ação pré-cadastrado, associado a uma Categoria de Grupo, oferecido como atalho ao criar Ação candidata ou avulsa (ex: "Ensaio", "Culto Jovem", "Acampamento"). Não obriga — quem cria pode digitar um nome livre.
_Avoid_: Template de ação, modelo de ação

**Grupo**:
Comunidade permanente organizada em torno de uma atividade recorrente (ex: SevenBikers, Asafe). Tem nome, horário padrão de encontro (recorrente, não um evento único), local e detalhes. Existe para que seus participantes possam propor e votar Ações.
_Avoid_: Comunidade, time

**Participar do Grupo**:
Associação leve e revogável de um Usuário a um Grupo — não é filiação formal nem permanente, o usuário entra e sai quando quiser. Concede três direitos: aparecer identificado no Grupo, propor Ação candidata no Grupo, e votar nas Ações candidatas do Grupo.
_Avoid_: Ser membro do grupo, entrar no grupo

**Dono do Grupo**:
Papel único por Grupo, atribuído a quem o criou e transferível depois para outro participante. Administra o Grupo: edita nome/horário/local/detalhes, remove participante, encerra Rodada de votação antes do prazo, e cancela Ação de Grupo (junto com quem propôs a candidata vencedora e o Administrador do distrito).
_Avoid_: Admin do grupo, moderador do grupo

**Ação**:
Evento pontual com data/hora específica, local e detalhes. Duas origens possíveis:
- **Ação de Grupo**: nasce como Ação candidata dentro de um Grupo (ver abaixo).
- **Ação avulsa**: criada por qualquer Usuário sem Grupo pai, sem votação, já confirmada e temporária.

Participar de uma Ação (confirmar presença) é aberto a qualquer Usuário cadastrado, esteja ele associado ao Grupo pai ou não; é revogável — o Usuário pode desistir depois, liberando a vaga. Pode ter um limite de vagas opcional, definido por quem cria; sem limite definido, é ilimitada. Vaga lotada forma fila de espera: se alguém desistir, o próximo da fila assume a vaga automaticamente. Ação avulsa é cancelada por quem a criou ou pelo Administrador do distrito; Ação de Grupo é cancelada por quem propôs a candidata vencedora, pelo Dono do Grupo, ou pelo Administrador do distrito.
_Avoid_: Grupo (não são sinônimos — Ação é pontual, Grupo é permanente), Evento, Atividade

**Ação candidata**:
Proposta de Ação dentro de um Grupo, concorrendo com outras candidatas dentro de uma Rodada de votação. Aceita tanto Votos quanto confirmação de presença (Participar) enquanto está em aberto — as duas coisas são independentes. A(s) candidata(s) vencedora(s) vira(m) Ação confirmada do Grupo, carregando as presenças já confirmadas; as demais são descartadas junto com suas presenças confirmadas. Só existe dentro de Grupo — Ação avulsa nunca passa por votação.

**Rodada de votação**:
Janela de tempo, aberta por qualquer participante de um Grupo, com prazo automático definido na abertura. Enquanto aberta, qualquer participante do Grupo pode propor novas Ações candidatas a qualquer momento. Um Grupo pode ter várias Rodadas abertas em paralelo, para Ações diferentes. Ao fechar, apura-se a candidata mais votada; empate é resolvido por sorteio aleatório entre as empatadas.

**Votar**:
Escolher entre Ações candidatas de uma Rodada de votação. Restrito aos Usuários que participam do Grupo dono da Rodada. Revogável — o Usuário pode trocar de candidata quantas vezes quiser enquanto a Rodada estiver aberta; só a última escolha conta na apuração.

**Igreja**:
Nome numa lista simples mantida pelo Administrador do distrito, sem outros atributos. Usuário escolhe uma no cadastro, ou nenhuma. Grupo e Ação também carregam uma Igreja, limitada à igreja do próprio criador (não escolhe qualquer uma das 15+ do distrito) — usada pra destaque/distribuição: Usuário da Igreja X vê em destaque Grupos/Ações vinculados à Igreja X, mas continua vendo normalmente os vinculados a outras igrejas. Não é restrição de acesso.

**Administrador do distrito**:
Único papel com privilégio acima dos Usuários comuns. Gerencia a lista de Igrejas do distrito, cuida de moderação e casos excepcionais, e pode cancelar qualquer Ação (além de quem a criou). Escopo exato de moderação ainda não detalhado. Exige Conta (não basta Perfil) — mesmo motivo do Líder/Diretor: papel público de alto privilégio, não pode se perder com reinstalação de aparelho. Diferente do Líder/Diretor: nunca autodeclaração — só um Administrador do distrito existente promove outro Usuário com Conta a Administrador. O primeiro Administrador do distrito é criado fora do fluxo normal do app (seed direto no banco/painel), já que não existe papel acima dele para aprovar.

**Ministério**:
Grupo que tem um Líder/Diretor. Grupos informais (ex: SevenBikers) não precisam de Líder; Ministério é o Grupo que tem. Identificação do Líder é pública na página do Ministério — visível até pra Visitante sem cadastro.

**Líder/Diretor**:
Papel de um Usuário num Ministério, com título anual: qualquer Usuário com Conta (não basta Perfil) se autodeclara Líder de um Ministério, o Administrador do distrito vê a lista de declarações pendentes e confirma (ou não). Título expira todo mês de janeiro — precisa redeclarar e ser reconfirmado a cada ano. Independente do Dono do Grupo: Líder é identificação oficial exibida no Ministério (quem é o responsável perante a igreja), Dono do Grupo é quem administra o Grupo no app — podem ser pessoas diferentes.
_Avoid_: Pastor, responsável

**Dupla Missionária**:
Ação com regra de composição por gênero, baseada no gênero de quem será visitado. Composições válidas: 1 homem + 1 mulher (serve para visitar qualquer pessoa), 2 homens (só válida se o visitado for homem), 2 mulheres (só válida se a visitada for mulher). 2 homens visitando mulher, ou 2 mulheres visitando homem, é inválido.
