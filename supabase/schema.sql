-- =========================================================
-- Agenda Manicure — esquema Supabase (Postgres)
-- Rode no SQL Editor do Supabase.
-- =========================================================

-- ---------- Clientes ----------
create table public.clients (
  id                         uuid primary key default gen_random_uuid(),
  user_id                    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name                       text not null,
  phone                      text,
  is_regular                 boolean not null default false,   -- cliente fixa/fiel
  maintenance_interval_days  int default 30,                   -- usado para sugerir o retorno
  notes                      text,
  created_at                 timestamptz not null default now()
);

-- ---------- Serviços (com preço padrão) ----------
create table public.services (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name           text not null,              -- ex: "Manutenção gel", "Pé", "Mão"
  default_price  numeric(10,2) not null default 0,
  duration_min   int not null default 90,
  active         boolean not null default true
);

-- ---------- Horários de trabalho (os "slots" fixos dela) ----------
-- Ex: seg 08:00, seg 10:00, seg 13:00, seg 15:00, seg 17:00
create table public.work_slots (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  weekday     smallint not null check (weekday between 1 and 7),  -- 1 = segunda ... 7 = domingo
  start_time  time not null,
  unique (user_id, weekday, start_time)
);

-- ---------- Agendamentos ----------
create type appointment_status as enum ('agendado', 'concluido', 'faltou', 'cancelado');

create table public.appointments (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  client_id    uuid references public.clients(id) on delete set null,
  client_name  text not null,               -- permite anotar rápido sem cadastrar a cliente
  starts_at    timestamptz not null,
  status       appointment_status not null default 'agendado',
  notes        text,
  created_at   timestamptz not null default now()
);
create index on public.appointments (user_id, starts_at);

-- Procedimentos de cada atendimento (mão + pé = 2 linhas).
-- price começa com o preço padrão e ela ajusta no fim do dia.
create table public.appointment_services (
  id              uuid primary key default gen_random_uuid(),
  appointment_id  uuid not null references public.appointments(id) on delete cascade,
  service_id      uuid references public.services(id) on delete set null,
  service_name    text not null,
  price           numeric(10,2) not null default 0
);

-- ---------- Despesas ----------
create type expense_category as enum ('aluguel', 'material', 'outro');

create table public.expenses (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  category     expense_category not null,
  description  text,
  amount       numeric(10,2) not null,
  spent_on     date not null default current_date
);

-- =========================================================
-- Segurança (RLS): cada usuária só vê os próprios dados
-- =========================================================
alter table public.clients              enable row level security;
alter table public.services             enable row level security;
alter table public.work_slots           enable row level security;
alter table public.appointments         enable row level security;
alter table public.appointment_services enable row level security;
alter table public.expenses             enable row level security;

create policy own_clients      on public.clients      for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_services     on public.services     for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_slots        on public.work_slots   for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_appointments on public.appointments for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_expenses     on public.expenses     for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_appt_services on public.appointment_services for all
  using (exists (select 1 from public.appointments a where a.id = appointment_id and a.user_id = auth.uid()))
  with check (exists (select 1 from public.appointments a where a.id = appointment_id and a.user_id = auth.uid()));

-- =========================================================
-- Fechamentos: dia, semana (seg–sáb) e mês
-- Só conta atendimentos "concluido". Fuso de Brasília.
-- =========================================================
create view public.revenue_by_day with (security_invoker = true) as
select a.user_id,
       (a.starts_at at time zone 'America/Sao_Paulo')::date as day,
       count(distinct a.id)                                   as atendimentos,
       coalesce(sum(s.price), 0)                              as faturamento
from public.appointments a
join public.appointment_services s on s.appointment_id = a.id
where a.status = 'concluido'
group by 1, 2;

create view public.revenue_by_week with (security_invoker = true) as
select user_id,
       date_trunc('week', day)::date as week_start,   -- segunda-feira
       sum(atendimentos)             as atendimentos,
       sum(faturamento)              as faturamento
from public.revenue_by_day
group by 1, 2;

create view public.monthly_summary with (security_invoker = true) as
with rev as (
  select user_id, date_trunc('month', day)::date as month,
         sum(atendimentos) as atendimentos, sum(faturamento) as faturamento
  from public.revenue_by_day group by 1, 2
), exp as (
  select user_id, date_trunc('month', spent_on)::date as month,
         sum(amount) filter (where category = 'aluguel')  as aluguel,
         sum(amount) filter (where category = 'material') as material,
         sum(amount) filter (where category = 'outro')    as outros,
         sum(amount)                                      as despesas
  from public.expenses group by 1, 2
)
select coalesce(r.user_id, e.user_id)          as user_id,
       coalesce(r.month, e.month)              as month,
       coalesce(r.atendimentos, 0)             as atendimentos,
       coalesce(r.faturamento, 0)              as faturamento,
       coalesce(e.aluguel, 0)                  as aluguel,
       coalesce(e.material, 0)                 as material,
       coalesce(e.outros, 0)                   as outros,
       coalesce(e.despesas, 0)                 as despesas,
       coalesce(r.faturamento, 0) - coalesce(e.despesas, 0) as lucro
from rev r
full join exp e on e.user_id = r.user_id and e.month = r.month;
