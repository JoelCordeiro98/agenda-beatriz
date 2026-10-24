-- =========================================================
-- Lembretes, forma de pagamento, fotos das unhas, bloqueios
-- e estatísticas por cliente.
-- Rode uma vez no SQL Editor do Supabase (pode rodar de novo sem problema).
-- =========================================================

-- ---------- Atendimentos: novos campos ----------
alter table public.appointments add column if not exists reminder_sent_at timestamptz;
alter table public.appointments add column if not exists payment_method  text;
alter table public.appointments add column if not exists nail_photo_path text;

alter table public.appointments drop constraint if exists appointments_payment_method_check;
alter table public.appointments add constraint appointments_payment_method_check
  check (payment_method is null
         or payment_method in ('pix', 'dinheiro', 'cartao', 'pendente'));

-- ---------- Bloqueios (feriado, médico, viagem...) ----------
-- start_time vazio = dia inteiro bloqueado
create table if not exists public.blocks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day         date not null,
  start_time  time,
  reason      text,
  created_at  timestamptz not null default now()
);
create index if not exists blocks_user_day on public.blocks (user_id, day);

alter table public.blocks enable row level security;
drop policy if exists own_blocks on public.blocks;
create policy own_blocks on public.blocks for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- Estatísticas por cliente ----------
create or replace view public.client_stats with (security_invoker = true) as
select c.id as client_id,
       c.user_id,
       max(a.starts_at) filter (where a.status = 'concluido')                         as last_visit,
       min(a.starts_at) filter (where a.status = 'agendado' and a.starts_at > now())  as next_visit,
       count(*)        filter (where a.status = 'concluido')                          as visits,
       count(*)        filter (where a.status = 'faltou')                             as no_shows,
       coalesce((select sum(s.price)
                   from public.appointments a2
                   join public.appointment_services s on s.appointment_id = a2.id
                  where a2.client_id = c.id and a2.status = 'concluido'), 0)          as total_spent
from public.clients c
left join public.appointments a on a.client_id = c.id
group by c.id, c.user_id;
