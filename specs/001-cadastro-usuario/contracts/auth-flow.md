# Contrato: Fluxo de Autenticação (Perfil ↔ Conta)

Estado observável pelo client em qualquer momento, via `supabase.auth.currentUser`:

```
sem sessão ──signInAnonymously()──▶ sessão anônima (auth.users.is_anonymous = true)
                                        │
                              INSERT perfis (id = auth.uid())
                                        │
                                        ▼
                              Perfil ativo, sem Conta
                                        │
                        updateUser(email/telefone + senha)
                                        │
                                        ▼
                     Conta ativa (auth.users.is_anonymous = false)
                     mesmo auth.uid(), mesma linha em perfis
```

## Regras de contrato

1. **App abre**: se não há sessão (`currentUser == null`), chamar
   `signInAnonymously()` antes de mostrar qualquer tela — isso acontece nos
   bastidores, a pessoa não vê "login". Se `auth.uid()` já existe mas não há
   linha em `perfis`, mostrar tela de cadastro (FR-001). Se já existe linha em
   `perfis`, ir direto pro app (FR-007, SC-004).
2. **Cadastro conclui** com um único `INSERT` em `perfis` com `id = auth.uid()`
   — nunca antes de `consentimento_lgpd_aceito_em` estar preenchido (FR-003) e
   nunca sem `apelido` se `idade < 18` (FR-005, garantido pela constraint).
3. **Upgrade pra Conta** é sempre opcional e nunca bloqueia nenhuma tela desta
   feature (FR-011). É oferecido/exigido só no fluxo de autodeclaração de
   Líder/Diretor (FR-012, fora de escopo desta feature — aqui só a capacidade
   existe).
4. **Login em outro aparelho**: só possível se `is_anonymous = false`
   (Conta). Client chama `signInWithPassword`/`signInWithOtp` normalmente; o
   `auth.uid()` retornado já resolve a mesma linha em `perfis` (FR-013).
5. **Erro de credencial** (FR-014): qualquer falha de login retorna mensagem
   genérica ("credenciais inválidas"), nunca especifica se o identificador ou
   a senha estava errada — isso é comportamento nativo do Supabase Auth, o
   client só precisa não tentar diferenciar a mensagem.
6. **Leitura de outro Usuário** (Grupo/Ação, features futuras): sempre via RPC
   `perfil_publico(id)`, nunca `select * from perfis where id = ...` — isso é
   estrutural (RLS bloqueia a segunda forma pra quem não é dono).
