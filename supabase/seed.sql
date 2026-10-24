-- Serviços da Beatriz Cordeiro (tabela de preços de out/2026).
-- Rode DEPOIS do schema.sql e de criar o usuário em Authentication > Users.
-- Durações em minutos são estimativas — ajuste se precisar.
-- Os horários de trabalho (seg–sáb: 8h, 10h, 13h, 15h, 17h) o app cria sozinho no primeiro acesso.

insert into public.services (user_id, name, default_price, duration_min)
select u.id, s.name, s.price, s.duration
from auth.users u,
     (values
        -- Serviços
        ('Aplicação em gel',         110.00, 150),
        ('Manutenção',                90.00, 120),
        ('Banho de gel',              90.00,  90),
        ('Esmaltação em gel',         50.00,  60),
        ('Pé e mão normal',           45.00,  90),
        ('Só mão',                    25.00,  45),
        ('Só pé',                     25.00,  45),
        ('Aplicação de postiça',      30.00,  60),
        -- Extras
        ('Remoção do gel',            30.00,  30),
        ('Reposição de unha',         10.00,  15),
        ('Mudança de formato',        10.00,  15),
        ('Decoração mais elaborada',  10.00,  20)
     ) as s(name, price, duration)
where u.email = 'joelcordeiro2016@hotmail.com';
