-- SMART AKADEMIA SCHOOL — Provisionnement administrateur sécurisé
-- À exécuter APRÈS AKADEMIA_supabase_setup.sql et AVANT de créer le compte Auth admin.
-- Adresse administrateur déjà renseignée : julio7271@gmail.com.
-- Aucun mot de passe ni clé secrète ne doit être placé dans ce fichier.

begin;

-- Un profil admin n'est pas un élève : valeur de série dédiée, inutilisable par les élèves.
alter table public.profiles drop constraint if exists profiles_series_check;
alter table public.profiles
    add constraint profiles_series_check
    check (series in (
        'Seconde', 'Première', 'Première L', 'Première S', 'Première OSE',
        'Terminale L', 'Terminale S', 'Terminale OSE', 'Administrateur'
    ));

-- Liste d'autorisation modifiable uniquement par le propriétaire du projet dans SQL Editor.
-- Le navigateur (anon/authenticated) ne peut ni lire ni modifier cette liste.
create table if not exists public.akademia_admin_allowlist (
    email text primary key,
    enabled boolean not null default true,
    created_at timestamptz not null default now(),
    constraint akademia_admin_allowlist_email_check
        check (email = lower(trim(email)) and email like '%@%')
);
alter table public.akademia_admin_allowlist enable row level security;
revoke all on table public.akademia_admin_allowlist from public, anon, authenticated;

-- Autoriser explicitement l'adresse du propriétaire avant la création de son compte Auth.
insert into public.akademia_admin_allowlist(email, enabled)
values (lower(trim('julio7271@gmail.com')), true)
on conflict (email) do update set enabled = true;

-- À la création Auth, seul un e-mail inscrit dans la liste privée reçoit le rôle admin.
-- Le rôle ne dépend JAMAIS de user_metadata fourni par le navigateur.
create or replace function public.handle_new_akademia_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    chosen_series text;
    approved_admin boolean;
begin
    select exists (
        select 1
        from public.akademia_admin_allowlist a
        where a.enabled = true
          and a.email = lower(trim(coalesce(new.email, '')))
    ) into approved_admin;

    if approved_admin then
        insert into public.profiles (
            id, email, full_name, phone, series, role,
            must_change_password, password_change_required_at
        ) values (
            new.id,
            coalesce(new.email, ''),
            coalesce(new.raw_user_meta_data->>'full_name', ''),
            nullif(new.raw_user_meta_data->>'phone', ''),
            'Administrateur',
            'admin',
            true,
            now()
        )
        on conflict (id) do update set
            email = excluded.email,
            role = 'admin',
            series = 'Administrateur',
            must_change_password = true,
            password_change_required_at = now();
        return new;
    end if;

    -- Tous les autres comptes doivent obligatoirement présenter une série élève valide.
    chosen_series := nullif(trim(coalesce(new.raw_user_meta_data->>'series', '')), '');
    if chosen_series is null or chosen_series not in (
        'Seconde', 'Première', 'Première L', 'Première S', 'Première OSE',
        'Terminale L', 'Terminale S', 'Terminale OSE'
    ) then
        raise exception 'Choisissez une classe et une série valides.';
    end if;

    insert into public.profiles (id, email, full_name, phone, series, role)
    values (
        new.id,
        coalesce(new.email, ''),
        coalesce(new.raw_user_meta_data->>'full_name', ''),
        nullif(new.raw_user_meta_data->>'phone', ''),
        chosen_series,
        'student'
    )
    on conflict (id) do update set
        email = excluded.email,
        full_name = excluded.full_name,
        phone = excluded.phone,
        series = excluded.series;

    return new;
end;
$$;

-- Si le compte Auth existait déjà avant cette migration, promouvoir UNIQUEMENT l'adresse
-- autorisée ci-dessus et forcer le changement du mot de passe au prochain accès.
insert into public.profiles (
    id, email, full_name, phone, series, role,
    must_change_password, password_change_required_at
)
select
    u.id,
    coalesce(u.email, ''),
    coalesce(u.raw_user_meta_data->>'full_name', ''),
    nullif(u.raw_user_meta_data->>'phone', ''),
    'Administrateur',
    'admin',
    true,
    now()
from auth.users u
join public.akademia_admin_allowlist a
  on a.enabled = true and a.email = lower(trim(coalesce(u.email, '')))
on conflict (id) do update set
    email = excluded.email,
    series = 'Administrateur',
    role = 'admin',
    must_change_password = true,
    password_change_required_at = now();

commit;

-- Vérification sans exposer de secret :
select p.email, p.role, p.series, p.must_change_password
from public.profiles p
join public.akademia_admin_allowlist a on a.email = lower(trim(p.email))
where a.enabled = true;
