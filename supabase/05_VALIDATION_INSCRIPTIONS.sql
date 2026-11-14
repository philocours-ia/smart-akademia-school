-- Migration 05 : validation obligatoire des nouvelles inscriptions élèves.
-- À exécuter après les migrations 01 à 04 dans Supabase SQL Editor.
-- Les comptes déjà présents sont conservés comme approuvés ; seuls les nouveaux
-- profils créés après cette migration commencent en attente.

alter table public.profiles
    add column if not exists registration_status text;

update public.profiles
   set registration_status = 'approved'
 where registration_status is null;

alter table public.profiles
    alter column registration_status set default 'pending',
    alter column registration_status set not null;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'profiles_registration_status_check'
          and conrelid = 'public.profiles'::regclass
    ) then
        alter table public.profiles
            add constraint profiles_registration_status_check
            check (registration_status in ('pending', 'approved', 'rejected'));
    end if;
end $$;

-- Toute nouvelle inscription Auth reste en attente. Le rôle student reste imposé
-- par le trigger existant ; aucune métadonnée navigateur ne peut auto-approuver.
create or replace function public.handle_new_akademia_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    chosen_series text;
begin
    chosen_series := nullif(trim(coalesce(new.raw_user_meta_data->>'series', '')), '');
    if chosen_series is null or chosen_series not in ('Seconde', 'Première L', 'Première S', 'Première OSE', 'Terminale L', 'Terminale S', 'Terminale OSE') then
        raise exception 'Choisissez une classe valide : Seconde, Première L, Première S, Première OSE, Terminale L, Terminale S ou Terminale OSE.';
    end if;

    insert into public.profiles (id, email, full_name, phone, series, role, registration_status)
    values (
        new.id,
        coalesce(new.email, ''),
        coalesce(new.raw_user_meta_data->>'full_name', ''),
        nullif(new.raw_user_meta_data->>'phone', ''),
        chosen_series,
        'student',
        'pending'
    )
    on conflict (id) do update set
        email = excluded.email,
        full_name = excluded.full_name,
        phone = excluded.phone,
        series = excluded.series;

    return new;
end;
$$;

-- Seul un administrateur dont le changement initial de mot de passe est terminé
-- peut prendre une décision. Fonction atomique côté base, sans droit UPDATE client.
create or replace function public.admin_decide_student_registration(
    target_user_id uuid,
    decision text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
    if not exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.role = 'admin'
          and p.must_change_password = false
    ) then
        raise exception 'Action réservée à un administrateur autorisé.';
    end if;

    if decision not in ('approved', 'rejected') then
        raise exception 'Décision invalide.';
    end if;

    update public.profiles
       set registration_status = decision
     where id = target_user_id
       and role = 'student'
       and registration_status = 'pending';

    if not found then
        raise exception 'Inscription introuvable ou déjà traitée.';
    end if;

    return true;
end;
$$;

revoke all on function public.admin_decide_student_registration(uuid, text) from public;
grant execute on function public.admin_decide_student_registration(uuid, text) to authenticated;

-- L'élève ne peut jamais modifier son statut ; lecture personnelle et lecture admin
-- restent régies par la politique profiles_select_self_or_admin existante.
revoke update (registration_status) on public.profiles from authenticated;
