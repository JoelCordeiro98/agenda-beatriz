-- =========================================================
-- Recuperação de senha por "palavra de recuperação" (sem e-mail)
-- Rode uma vez no SQL Editor do Supabase.
-- =========================================================

create extension if not exists pgcrypto with schema extensions;

-- Guarda só o "hash" da palavra (ninguém consegue ler a palavra original).
create table if not exists public.account_recovery (
  user_id          uuid primary key references auth.users(id) on delete cascade,
  email            text not null unique,
  answer_hash      text not null,
  failed_attempts  int not null default 0,
  locked_until     timestamptz,
  updated_at       timestamptz not null default now()
);

-- Sem políticas: o app não lê nem escreve essa tabela direto,
-- só pelas funções abaixo.
alter table public.account_recovery enable row level security;

-- ---------------------------------------------------------
-- Define/troca a palavra (usuária logada)
-- ---------------------------------------------------------
create or replace function public.set_recovery_word(word text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if length(trim(coalesce(word, ''))) < 3 then
    raise exception 'word_too_short';
  end if;

  select email into v_email from auth.users where id = auth.uid();

  insert into public.account_recovery (user_id, email, answer_hash)
  values (auth.uid(), lower(v_email), crypt(lower(trim(word)), gen_salt('bf')))
  on conflict (user_id) do update
    set email = excluded.email,
        answer_hash = excluded.answer_hash,
        failed_attempts = 0,
        locked_until = null,
        updated_at = now();
end;
$$;

-- ---------------------------------------------------------
-- A usuária logada já tem palavra cadastrada?
-- ---------------------------------------------------------
create or replace function public.has_recovery_word()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (select 1 from public.account_recovery where user_id = auth.uid());
$$;

-- ---------------------------------------------------------
-- Troca a senha usando e-mail + palavra (sem estar logada).
-- 5 erros seguidos bloqueiam por 30 minutos.
-- ---------------------------------------------------------
create or replace function public.reset_password_with_word(
  p_email text,
  p_word text,
  p_new_password text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id  uuid;
  v_hash     text;
  v_failed   int;
  v_locked   timestamptz;
  v_attempts int;
begin
  if length(coalesce(p_new_password, '')) < 6 then
    raise exception 'weak_password';
  end if;

  select ar.user_id, ar.answer_hash, ar.failed_attempts, ar.locked_until
    into v_user_id, v_hash, v_failed, v_locked
    from public.account_recovery ar
   where ar.email = lower(trim(p_email))
     for update;

  if v_user_id is null then
    perform pg_sleep(1);
    return false;
  end if;

  if v_locked is not null and v_locked > now() then
    raise exception 'locked';
  end if;

  if v_hash <> crypt(lower(trim(coalesce(p_word, ''))), v_hash) then
    -- se um bloqueio antigo já venceu, recomeça a contagem
    v_attempts := case when v_locked is not null then 1 else v_failed + 1 end;
    update public.account_recovery
       set failed_attempts = v_attempts,
           locked_until = case when v_attempts >= 5
                               then now() + interval '30 minutes' end
     where user_id = v_user_id;
    perform pg_sleep(1);
    return false;
  end if;

  update auth.users
     set encrypted_password = crypt(p_new_password, gen_salt('bf')),
         updated_at = now()
   where id = v_user_id;

  update public.account_recovery
     set failed_attempts = 0, locked_until = null
   where user_id = v_user_id;

  return true;
end;
$$;

-- ---------------------------------------------------------
-- Quem pode chamar cada função
-- ---------------------------------------------------------
revoke all on function public.set_recovery_word(text) from public, anon;
grant execute on function public.set_recovery_word(text) to authenticated;

revoke all on function public.has_recovery_word() from public, anon;
grant execute on function public.has_recovery_word() to authenticated;

revoke all on function public.reset_password_with_word(text, text, text) from public;
grant execute on function public.reset_password_with_word(text, text, text) to anon, authenticated;
