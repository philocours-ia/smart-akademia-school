-- SMART AKADEMIA SCHOOL
-- Backend Supabase : profils, droits administrateur, abonnements, messages et preuves de paiement.
-- À exécuter une seule fois dans Supabase > SQL Editor.
-- La clé service_role ne doit JAMAIS être insérée dans le fichier HTML.

create extension if not exists pgcrypto;

-- 1. PROFILS : un profil est créé automatiquement à l'inscription Auth.
create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    email text not null unique,
    full_name text not null default '',
    phone text,
    series text not null
        check (series in ('Seconde', 'Première', 'Première L', 'Première S', 'Première OSE', 'Terminale L', 'Terminale S', 'Terminale OSE')),
    role text not null default 'student'
        check (role in ('student', 'admin')),
    created_at timestamptz not null default now()
);

alter table public.profiles
    add column if not exists must_change_password boolean not null default false,
    add column if not exists password_change_required_at timestamptz;

alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
revoke update (series) on public.profiles from authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

-- Cette fonction permet aux politiques RLS de vérifier le rôle admin sans exposer les profils.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.role = 'admin'
          and p.must_change_password = false
    );
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Déverrouillage du compte admin déclenché côté base après une vraie modification du hash de mot de passe Auth.
-- On ne se fie pas à un champ modifiable depuis le navigateur ni à auth.users.updated_at.
create or replace function public.handle_akademia_admin_password_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.encrypted_password is distinct from old.encrypted_password then
        update public.profiles
           set must_change_password = false,
               password_change_required_at = null
         where id = new.id
           and role = 'admin'
           and must_change_password = true;
    end if;
    return new;
end;
$$;
revoke all on function public.handle_akademia_admin_password_changed() from public;

drop trigger if exists on_akademia_admin_password_changed on auth.users;
create trigger on_akademia_admin_password_changed
after update of encrypted_password on auth.users
for each row
when (old.encrypted_password is distinct from new.encrypted_password)
execute procedure public.handle_akademia_admin_password_changed();

-- RPC de confirmation : elle ne peut pas désactiver elle-même le verrou.
-- Elle vérifie seulement que le trigger Auth a déjà effacé must_change_password.
create or replace function public.complete_admin_password_change()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    pending boolean;
begin
    select p.must_change_password into pending
    from public.profiles p
    where p.id = auth.uid() and p.role = 'admin';

    if not found then
        raise exception 'Profil administrateur introuvable.';
    end if;
    if pending then
        raise exception 'La base n’a pas confirmé la modification du mot de passe Supabase Auth.';
    end if;
    return true;
end;
$$;
revoke all on function public.complete_admin_password_change() from public;
grant execute on function public.complete_admin_password_change() to authenticated;

drop policy if exists profiles_select_self_or_admin on public.profiles;
create policy profiles_select_self_or_admin
on public.profiles for select to authenticated
using (id = auth.uid() or public.is_admin());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self
on public.profiles for update to authenticated
using (id = auth.uid())
with check (id = auth.uid() and role = 'student');

-- Le rôle est défini côté serveur à student, jamais depuis les métadonnées envoyées par le navigateur.
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

drop trigger if exists on_auth_user_created_akademia on auth.users;
create trigger on_auth_user_created_akademia
after insert on auth.users
for each row execute procedure public.handle_new_akademia_user();

-- Rattrapage des comptes Auth éventuellement créés avant l'installation du trigger.
insert into public.profiles (id, email, full_name, phone, series, role)
select
    u.id,
    coalesce(u.email, ''),
    coalesce(u.raw_user_meta_data->>'full_name', ''),
    nullif(u.raw_user_meta_data->>'phone', ''),
    case
        when u.raw_user_meta_data->>'series' in ('Seconde', 'Première', 'Première L', 'Première S', 'Première OSE', 'Terminale L', 'Terminale S', 'Terminale OSE')
            then u.raw_user_meta_data->>'series'
        else 'Terminale L' -- valeur de reprise uniquement pour les anciens comptes sans classe ; les nouvelles inscriptions sont strictement validées par le trigger.
    end,
    'student'
from auth.users u
on conflict (id) do nothing;

-- 2. ABONNEMENTS : les élèves déposent leur preuve ; seul un administrateur peut valider.
create table if not exists public.subscriptions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    full_name text not null,
    series text not null check (series in ('Seconde', 'Première', 'Première L', 'Première S', 'Première OSE', 'Terminale L', 'Terminale S', 'Terminale OSE')),
    phone text not null,
    payment_method text not null check (payment_method in ('MVola', 'Binance Pay')),
    reference_code text not null check (reference_code = 'AKADEMIA'),
    transaction_reference text,
    proof_path text not null,
    proof_name text not null,
    status text not null default 'en_attente'
        check (status in ('en_attente', 'actif', 'refuse')),
    created_at timestamptz not null default now(),
    activated_at timestamptz,
    expires_at timestamptz
);

create index if not exists subscriptions_user_status_idx
    on public.subscriptions (user_id, status, expires_at);
create index if not exists subscriptions_created_at_idx
    on public.subscriptions (created_at desc);

alter table public.subscriptions enable row level security;
revoke all on public.subscriptions from anon, authenticated;
grant select on public.subscriptions to authenticated;
grant insert (
    user_id, full_name, series, phone, payment_method,
    reference_code, transaction_reference, proof_path, proof_name
) on public.subscriptions to authenticated;
grant update (status, activated_at, expires_at) on public.subscriptions to authenticated;

drop policy if exists subscriptions_select_owner_or_admin on public.subscriptions;
create policy subscriptions_select_owner_or_admin
on public.subscriptions for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists subscriptions_insert_own_pending on public.subscriptions;
create policy subscriptions_insert_own_pending
on public.subscriptions for insert to authenticated
with check (
    user_id = auth.uid()
    and reference_code = 'AKADEMIA'
    and status = 'en_attente'
    and split_part(proof_path, '/', 1) = auth.uid()::text
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'student' and p.series = subscriptions.series)
);

drop policy if exists subscriptions_update_admin_only on public.subscriptions;
create policy subscriptions_update_admin_only
on public.subscriptions for update to authenticated
using (public.is_admin())
with check (public.is_admin());

-- 3. MESSAGES ÉLÈVE-PROF : lecture par l'élève concerné et par l'administrateur.
create table if not exists public.student_messages (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    student_name text not null,
    series text not null check (series in ('Seconde', 'Première', 'Première L', 'Première S', 'Première OSE', 'Terminale L', 'Terminale S', 'Terminale OSE')),
    theme text not null,
    question text not null,
    reply text,
    created_at timestamptz not null default now(),
    replied_at timestamptz
);

create index if not exists student_messages_user_created_idx
    on public.student_messages (user_id, created_at desc);

alter table public.student_messages enable row level security;
revoke all on public.student_messages from anon, authenticated;
grant select on public.student_messages to authenticated;
grant insert (user_id, student_name, series, theme, question)
    on public.student_messages to authenticated;
grant update (reply, replied_at) on public.student_messages to authenticated;

drop policy if exists student_messages_select_owner_or_admin on public.student_messages;
create policy student_messages_select_owner_or_admin
on public.student_messages for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists student_messages_insert_own on public.student_messages;
create policy student_messages_insert_own
on public.student_messages for insert to authenticated
with check (
    user_id = auth.uid()
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'student' and p.series = student_messages.series)
);

drop policy if exists student_messages_update_admin_only on public.student_messages;
create policy student_messages_update_admin_only
on public.student_messages for update to authenticated
using (public.is_admin())
with check (public.is_admin());

-- 4. CITATIONS PERSONNALISÉES ET FORUM : contenus partagés entre tous les comptes.
create table if not exists public.custom_citations (
    id uuid primary key default gen_random_uuid(),
    created_by uuid not null references auth.users(id) on delete restrict,
    theme text not null,
    subtheme text not null,
    author text not null,
    malagasy_text text not null,
    french_text text not null,
    created_at timestamptz not null default now()
);
alter table public.custom_citations enable row level security;
revoke all on public.custom_citations from anon, authenticated;
grant select on public.custom_citations to authenticated;
grant insert (created_by, theme, subtheme, author, malagasy_text, french_text) on public.custom_citations to authenticated;
grant delete on public.custom_citations to authenticated;
drop policy if exists custom_citations_select_authenticated on public.custom_citations;
create policy custom_citations_select_authenticated on public.custom_citations
for select to authenticated using (true);
drop policy if exists custom_citations_insert_admin on public.custom_citations;
create policy custom_citations_insert_admin on public.custom_citations
for insert to authenticated with check (public.is_admin() and created_by = auth.uid());
drop policy if exists custom_citations_delete_admin on public.custom_citations;
create policy custom_citations_delete_admin on public.custom_citations
for delete to authenticated using (public.is_admin());

create table if not exists public.forum_debates (
    id uuid primary key default gen_random_uuid(),
    created_by uuid not null references auth.users(id) on delete restrict,
    theme text not null,
    title text not null,
    description text not null,
    created_at timestamptz not null default now()
);
alter table public.forum_debates enable row level security;
revoke all on public.forum_debates from anon, authenticated;
grant select on public.forum_debates to authenticated;
grant insert (created_by, theme, title, description) on public.forum_debates to authenticated;
grant delete on public.forum_debates to authenticated;
drop policy if exists forum_debates_select_authenticated on public.forum_debates;
create policy forum_debates_select_authenticated on public.forum_debates
for select to authenticated using (true);
drop policy if exists forum_debates_insert_admin on public.forum_debates;
create policy forum_debates_insert_admin on public.forum_debates
for insert to authenticated with check (public.is_admin() and created_by = auth.uid());
drop policy if exists forum_debates_delete_admin on public.forum_debates;
create policy forum_debates_delete_admin on public.forum_debates
for delete to authenticated using (public.is_admin());

create table if not exists public.forum_comments (
    id uuid primary key default gen_random_uuid(),
    debate_id uuid not null references public.forum_debates(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    author_name text not null default '',
    comment_text text not null,
    created_at timestamptz not null default now()
);
alter table public.forum_comments enable row level security;
revoke all on public.forum_comments from anon, authenticated;
grant select on public.forum_comments to authenticated;
grant insert (debate_id, user_id, comment_text) on public.forum_comments to authenticated;
drop policy if exists forum_comments_select_authenticated on public.forum_comments;
create policy forum_comments_select_authenticated on public.forum_comments
for select to authenticated using (true);
drop policy if exists forum_comments_insert_own on public.forum_comments;
create policy forum_comments_insert_own on public.forum_comments
for insert to authenticated with check (user_id = auth.uid() and exists (select 1 from public.forum_debates d where d.id = debate_id));

create or replace function public.set_akademia_forum_comment_author()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    select coalesce(p.full_name, '') into new.author_name
    from public.profiles p where p.id = new.user_id;
    return new;
end;
$$;
drop trigger if exists forum_comment_set_author on public.forum_comments;
create trigger forum_comment_set_author before insert on public.forum_comments
for each row execute procedure public.set_akademia_forum_comment_author();

-- 5. STOCKAGE PRIVÉ DES PREUVES DE PAIEMENT.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'payment-proofs',
    'payment-proofs',
    false,
    716800,
    array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'application/pdf']
)
on conflict (id) do update set
    public = false,
    file_size_limit = 716800,
    allowed_mime_types = excluded.allowed_mime_types;

grant select, insert, delete on storage.objects to authenticated;

drop policy if exists payment_proofs_insert_own_folder on storage.objects;
create policy payment_proofs_insert_own_folder
on storage.objects for insert to authenticated
with check (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists payment_proofs_select_owner_or_admin on storage.objects;
create policy payment_proofs_select_owner_or_admin
on storage.objects for select to authenticated
using (
    bucket_id = 'payment-proofs'
    and (
        (storage.foldername(name))[1] = auth.uid()::text
        or public.is_admin()
    )
);

drop policy if exists payment_proofs_delete_owner_or_admin on storage.objects;
create policy payment_proofs_delete_owner_or_admin
on storage.objects for delete to authenticated
using (
    bucket_id = 'payment-proofs'
    and (
        (storage.foldername(name))[1] = auth.uid()::text
        or public.is_admin()
    )
);

-- 6. APRÈS avoir créé le compte Auth de l'enseignant dans Supabase,
-- exécuter séparément cette instruction en remplaçant l'adresse par la vôtre :
-- update public.profiles
-- set role = 'admin', must_change_password = true, password_change_required_at = now()
-- where email = 'VOTRE_ADRESSE_ADMIN';
-- Vérifier ensuite : select id, email, role, must_change_password from public.profiles where role = 'admin';
-- L'administrateur se connecte avec le login affiché « akademia » et le mot de passe temporaire communiqué séparément au propriétaire.
-- Il doit le changer pour un mot de passe d'au moins 12 caractères avant d'accéder au tableau de bord; le trigger auth.users efface alors le verrou côté serveur.

-- ============================================================================
-- 7. SUIVI PÉDAGOGIQUE DES ÉLÈVES
-- Chaque ligne indique si un élève a terminé une leçon du PE T12.
-- ============================================================================
create table if not exists public.student_progress (
    user_id uuid not null references auth.users(id) on delete cascade,
    lesson_id text not null,
    lesson_title text not null default '',
    theme_title text not null default '',
    completed boolean not null default false,
    updated_at timestamptz not null default now(),
    primary key (user_id, lesson_id)
);

alter table public.student_progress enable row level security;
revoke all on public.student_progress from anon, authenticated;
grant select, insert, update on public.student_progress to authenticated;

drop policy if exists student_progress_select_owner_or_admin on public.student_progress;
create policy student_progress_select_owner_or_admin
on public.student_progress for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists student_progress_insert_own on public.student_progress;
create policy student_progress_insert_own
on public.student_progress for insert to authenticated
with check (user_id = auth.uid() or public.is_admin());

drop policy if exists student_progress_update_owner_or_admin on public.student_progress;
create policy student_progress_update_owner_or_admin
on public.student_progress for update to authenticated
using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

create or replace function public.touch_student_progress_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists student_progress_touch_updated_at on public.student_progress;
create trigger student_progress_touch_updated_at
before update on public.student_progress
for each row execute procedure public.touch_student_progress_updated_at();

-- ============================================================================
-- 8. TICKET D'ACCÈS À CHAQUE ACTIVATION / RENOUVELLEMENT D'ABONNEMENT
-- Chaque demande de renouvellement est une nouvelle ligne dans subscriptions.
-- Lorsqu'un administrateur la valide, un ticket unique est généré côté serveur
-- et l'abonnement est activé pour 30 jours. Le ticket est un reçu d'activation,
-- pas un mot de passe : l'élève se connecte avec son compte personnel.
-- ============================================================================
alter table public.subscriptions
    add column if not exists access_ticket text;

create unique index if not exists subscriptions_access_ticket_unique
    on public.subscriptions (access_ticket)
    where access_ticket is not null;

create or replace function public.issue_akademia_access_ticket()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    current_expiry timestamptz;
begin
    if new.status = 'actif' and new.access_ticket is null then
        new.access_ticket := 'AKD-' || to_char(clock_timestamp(), 'YYMMDD') || '-' || upper(encode(gen_random_bytes(5), 'hex'));
        new.activated_at := coalesce(new.activated_at, now());
        if new.expires_at is null then
            select max(s.expires_at) into current_expiry
            from public.subscriptions s
            where s.user_id = new.user_id
              and s.id <> new.id
              and s.status = 'actif'
              and s.expires_at > now();
            new.expires_at := greatest(now(), coalesce(current_expiry, now())) + interval '30 days';
        end if;
    end if;
    return new;
end;
$$;

revoke all on function public.issue_akademia_access_ticket() from public;

drop trigger if exists subscriptions_issue_ticket on public.subscriptions;
create trigger subscriptions_issue_ticket
before insert or update of status on public.subscriptions
for each row execute procedure public.issue_akademia_access_ticket();

-- Ticket rétroactif pour les abonnements déjà actifs avant cette mise à jour.
update public.subscriptions
set status = 'actif'
where status = 'actif' and access_ticket is null;

-- 9. Vue pratique des abonnements actifs / expirés pour les contrôles côté SQL.
create or replace view public.student_subscription_status
with (security_invoker = true) as
select
    s.id,
    s.user_id,
    s.status,
    s.access_ticket,
    s.activated_at,
    s.expires_at,
    case
        when s.status = 'actif' and s.expires_at > now() then 'actif'
        when s.status = 'actif' and s.expires_at <= now() then 'expire'
        else s.status
    end as effective_status,
    case
        when s.status = 'actif' and s.expires_at > now()
            then greatest(0, ceil(extract(epoch from (s.expires_at - now())) / 86400)::integer)
        else 0
    end as days_remaining
from public.subscriptions s;
revoke all on public.student_subscription_status from public, anon;
grant select on public.student_subscription_status to authenticated;

-- 10. COMPTE ADMINISTRATEUR : création et attribution du rôle (une seule fois).
-- Dans Supabase > Authentication > Users, créez/confirmez l'utilisateur avec :
--   mot de passe temporaire : celui communiqué séparément au propriétaire (à remplacer dès la première connexion)
--   adresse e-mail       : votre adresse admin choisie
-- Puis attribuez le rôle admin et imposez le changement du mot de passe :
-- update public.profiles set role='admin', must_change_password=true, password_change_required_at=now() where email='votre-adresse@email.com';
-- Enfin, recopiez cette même adresse dans SUPABASE_CONFIG.adminEmail du fichier HTML.
-- Le nom de connexion demandé dans le portail est « akademia » ; il est mappé
-- vers cette adresse Auth privée. Le mot de passe n'est jamais stocké dans le HTML.


-- ============================================================================
-- 11. CONTENU DES COURS ET CALENDRIER DE MISE À DISPOSITION (GOUVERNÉS PAR SUPABASE)
-- Les corps de leçons ne sont plus incorporés dans le HTML public.
-- Aucun cours n'est accessible sans abonnement actif ET date de sortie atteinte.
-- La table course_release_schedule reste vide jusqu'à validation des corps de cours
-- et des dates calendaires issues des RAPE T10/T11/T12 pour chaque série.
-- ============================================================================

create table if not exists public.course_lesson_content (
    lesson_id text primary key,
    source_theme_id text not null,
    content_html text not null,
    updated_at timestamptz not null default now()
);

create table if not exists public.course_release_schedule (
    series text not null check (series in ('Seconde', 'Première', 'Première L', 'Première S', 'Première OSE', 'Terminale L', 'Terminale S', 'Terminale OSE')),
    lesson_id text not null references public.course_lesson_content(lesson_id) on delete cascade,
    release_at timestamptz not null,
    release_note text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (series, lesson_id)
);

alter table public.course_release_schedule drop constraint if exists course_release_schedule_series_check;
alter table public.course_release_schedule add constraint course_release_schedule_series_check check (series in ('Seconde', 'Première', 'Première L', 'Première S', 'Première OSE', 'Terminale L', 'Terminale S', 'Terminale OSE'));

create index if not exists course_release_schedule_series_date_idx
    on public.course_release_schedule (series, release_at);

alter table public.course_lesson_content enable row level security;
alter table public.course_release_schedule enable row level security;
revoke all on public.course_lesson_content from anon, authenticated;
revoke all on public.course_release_schedule from anon, authenticated;
grant select, insert, update, delete on public.course_lesson_content to authenticated;
grant select, insert, update, delete on public.course_release_schedule to authenticated;

-- Contrôle serveur : l'abonnement doit être réellement actif et non expiré.
create or replace function public.has_active_akademia_subscription()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.subscriptions s
        where s.user_id = auth.uid()
          and s.status = 'actif'
          and s.expires_at > now()
    );
$$;
revoke all on function public.has_active_akademia_subscription() from public;
grant execute on function public.has_active_akademia_subscription() to authenticated;

-- Contrôle serveur par leçon : série personnelle + abonnement actif + date atteinte.
create or replace function public.can_access_akademia_lesson(p_lesson_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select public.is_admin() or (
        public.has_active_akademia_subscription()
        and exists (
            select 1
            from public.profiles p
            join public.course_release_schedule r on r.series = p.series
            where p.id = auth.uid()
              and p.role = 'student'
              and r.lesson_id = p_lesson_id
              and r.release_at <= now()
        )
    );
$$;
revoke all on function public.can_access_akademia_lesson(text) from public;
grant execute on function public.can_access_akademia_lesson(text) to authenticated;

-- Les élèves abonnés peuvent voir le calendrier de leur série, y compris les dates futures.
-- Sans abonnement actif, même le calendrier détaillé reste masqué.
drop policy if exists course_schedule_select_own_series_or_admin on public.course_release_schedule;
create policy course_schedule_select_own_series_or_admin
on public.course_release_schedule for select to authenticated
using (
    public.is_admin()
    or (
        public.has_active_akademia_subscription()
        and series = (select p.series from public.profiles p where p.id = auth.uid() and p.role = 'student')
    )
);
drop policy if exists course_schedule_admin_manage on public.course_release_schedule;
create policy course_schedule_admin_manage
on public.course_release_schedule for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Les corps de cours ne sont servis qu'après contrôle de la date et de l'abonnement.
drop policy if exists course_content_select_released_or_admin on public.course_lesson_content;
create policy course_content_select_released_or_admin
on public.course_lesson_content for select to authenticated
using (public.can_access_akademia_lesson(lesson_id));
drop policy if exists course_content_admin_manage on public.course_lesson_content;
create policy course_content_admin_manage
on public.course_lesson_content for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- La progression d'un élève ne peut être créée ou modifiée que sur une leçon ouverte.
drop policy if exists student_progress_insert_own on public.student_progress;
create policy student_progress_insert_own
on public.student_progress for insert to authenticated
with check (
    (user_id = auth.uid() and public.can_access_akademia_lesson(lesson_id))
    or public.is_admin()
);
drop policy if exists student_progress_update_owner_or_admin on public.student_progress;
create policy student_progress_update_owner_or_admin
on public.student_progress for update to authenticated
using (user_id = auth.uid() or public.is_admin())
with check (
    (user_id = auth.uid() and public.can_access_akademia_lesson(lesson_id))
    or public.is_admin()
);

-- Contenus existants migrés depuis l'ancien HTML vers la table privée.
-- Ils sont insérés maintenant, mais ne seront livrés à aucun élève avant
-- d'avoir une ligne de calendrier et que sa date de sortie soit atteinte.
insert into public.course_lesson_content (lesson_id, source_theme_id, content_html)
values
    ('t1c1', 'them1', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+MS4gRMOpZmluaXRpb24gw6l0eW1vbG9naXF1ZTwvaDQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8cCBjbGFzcz0ibWItMyI+RGUgc29uIHNlbnMgw6l0eW1vbG9naXF1ZSwgbGUgbW90IMKrIHBoaWxvc29waGllIMK7IHZpZW50IGR1IGdyZWMgPGVtPnBoaWxlaW48L2VtPiAoYWltZXIsIGTDqXNpcmVyKSBldCA8ZW0+c29waGlhPC9lbT4gKHNhZ2Vzc2UpLCBzaWduaWZpYW50IDxzdHJvbmc+wqsgbCdhbW91ciBkZSBsYSBzYWdlc3NlIMK7PC9zdHJvbmc+LiBDZXR0ZSBkw6lmaW5pdGlvbiBmdXQgYXR0cmlidcOpZSBwb3VyIGxhIHByZW1pw6hyZSBmb2lzIHBhciA8c3Ryb25nPlB5dGhhZ29yZTwvc3Ryb25nPiBhdSBWZSBzacOoY2xlIGF2YW50IEouLUMuLCByZWZ1c2FudCBsZSB0aXRyZSBkZSDCqyBzYWdlIMK7ICg8ZW0+c29waG9zPC9lbT4pIHLDqXNlcnbDqSBhdXggc2V1bHMgZGlldXgsIHBvdXIgc2UgZGlyZSDCqyBhbWkgZGUgbGEgc2FnZXNzZSDCuyAoPGVtPnBoaWxvc29waG9zPC9lbT4pLjwvcD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxoNCBjbGFzcz0iZm9udC1ib2xkIHRleHQtbmF2eS05MDAgdGV4dC1sZyBtYi0yIj4yLiBMZSBkb3VibGUgYXNwZWN0IGRlIGxhIHNhZ2Vzc2U8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHVsIGNsYXNzPSJsaXN0LWRpc2MgcGwtNSBzcGFjZS15LTIgbWItMyI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPGxpPjxzdHJvbmc+TGEgc2FnZXNzZSB0aMOpb3JpcXVlIDo8L3N0cm9uZz4gRWxsZSBzZSByYXBwb3J0ZSBhdXggZWZmb3J0cyBkZSBsYSByYWlzb24gaHVtYWluZSBhZmluIGQnYWNxdcOpcmlyIHVuZSBjb25jZXB0aW9uIGQnZW5zZW1ibGUgZXQgZ2xvYmFsZSBkZSBsJ3VuaXZlcnMgKGNoZXogbGVzIFByw6lzb2NyYXRpcXVlcywgc2FnZXNzZSDDqXRhaXQgc3lub255bWUgZGUgc2NpZW5jZSkuPC9saT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8bGk+PHN0cm9uZz5MYSBzYWdlc3NlIHByYXRpcXVlIDo8L3N0cm9uZz4gRWxsZSBlc3QgdW4gZWZmb3J0IHBvdXIgw6lsYWJvcmVyIHVuZSByw6hnbGUgZGUgdmllLCBwb3VyIGFkb3B0ZXIgdW5lIGNvbmR1aXRlIHLDqWZsw6ljaGllIGV0IHJhaXNvbm5hYmxlLiBTYWdlIGVzdCBjZWx1aSBxdWkgc2FpdCBjb25kdWlyZSBzYSB2aWUgc2Vsb24gbGEgcmFpc29uLjwvbGk+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L3VsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPGRpdiBjbGFzcz0iYmctYW1iZXItNTAgYm9yZGVyLWwtNCBib3JkZXItZ29sZC01MDAgcC0zIHJvdW5kZWQtci14bCB0ZXh0LXhzIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8c3Ryb25nPsOAIHJldGVuaXIgcG91ciBsZSBCYWNjIDo8L3N0cm9uZz4gU2Vsb24gS2FybCBKYXNwZXJzLCDCqyBsJ2Vzc2VuY2UgZGUgbGEgcGhpbG9zb3BoaWUgZXN0IGxhIHJlY2hlcmNoZSBkZSBsYSB2w6lyaXTDqSBldCBub24gc2EgcG9zc2Vzc2lvbiDCuy4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvZGl2PgogICAgICAgICAgICAgICAgICAgICAgICA=', 'base64'), 'UTF8')),
    ('t1c2', 'them1', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+MS4gTCdhY3RlIGRlIHBoaWxvc29waGVyIHNvY3JhdGlxdWU8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHAgY2xhc3M9Im1iLTMiPkF2ZWMgPHN0cm9uZz5Tb2NyYXRlPC9zdHJvbmc+LCBww6hyZSBkZSBsYSBwaGlsb3NvcGhpZSBvY2NpZGVudGFsZSwgbCdob21tZSBkZXZpZW50IGwnb2JqZXQgcHJpdmlsw6lnacOpIGRlIGxhIHLDqWZsZXhpb24uIFBoaWxvc29waGVyIGNvbnNpc3RlIMOgIHLDqWZsw6ljaGlyIChhdXRvY3JpdGlxdWUsIMKrIGNvbm5haXMtdG9pIHRvaS1tw6ptZSDCuykgZXQgw6AgcHJhdGlxdWVyIGwnPHN0cm9uZz5pcm9uaWU8L3N0cm9uZz4gZXQgbGEgPHN0cm9uZz5tYcOvZXV0aXF1ZTwvc3Ryb25nPiAobCdhcnQgZCdhY2NvdWNoZXIgbGVzIGVzcHJpdHMpLjwvcD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxoNCBjbGFzcz0iZm9udC1ib2xkIHRleHQtbmF2eS05MDAgdGV4dC1sZyBtYi0yIj4yLiBMZXMgZGltZW5zaW9ucyBkZSBsYSBwaGlsb3NvcGhpZTwvaDQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8dWwgY2xhc3M9Imxpc3QtZGlzYyBwbC01IHNwYWNlLXktMiBtYi0zIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8bGk+PHN0cm9uZz5Sw6lmbGV4aW9uIGRlIHNlY29uZCBkZWdyw6kgKMOJcGlzdMOpbW9sb2dpZSkgOjwvc3Ryb25nPiDDiXR1ZGUgY3JpdGlxdWUgZGVzIHNjaWVuY2VzLCBkZSBsZXVycyBtw6l0aG9kZXMgZXQgZGUgbGV1cnMgY29uc8OpcXVlbmNlcyBodW1haW5lcy48L2xpPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxsaT48c3Ryb25nPlJlY2hlcmNoZSByYXRpb25uZWxsZSBkZSBsYSB2w6lyaXTDqSA6PC9zdHJvbmc+IFBsYXRvbiBkaXN0aW5ndWUgbGEgPGVtPnLDqWFsaXTDqSBzZW5zaWJsZTwvZW0+ICh0cm9tcGV1c2UsIGFwcGFyZW5jZXMpIGRlIGxhIDxlbT5yw6lhbGl0w6kgaW50ZWxsaWdpYmxlPC9lbT4gKGltbXVhYmxlLCBsJ8OKdHJlKS48L2xpPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxsaT48c3Ryb25nPkludGVycm9nYXRpb24gc3VyIGxlIHLDqWVsIGV0IGFydCBkZSB2aXZyZSA6PC9zdHJvbmc+IMKrIE51bCBuJ2VzdCBtw6ljaGFudCB2b2xvbnRhaXJlbWVudCDCuyAoU29jcmF0ZSkuIExhIHBoaWxvc29waGllIHZpc2UgbGUgYm9uaGV1ciBkdXJhYmxlIHBhciBsYSBtYcOudHJpc2UgZGVzIHBhc3Npb25zLjwvbGk+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L3VsPgogICAgICAgICAgICAgICAgICAgICAgICA=', 'base64'), 'UTF8')),
    ('t1c3', 'them1', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+MS4gTGUgZG9tYWluZSB1bml2ZXJzZWw8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHAgY2xhc3M9Im1iLTMiPkRlc2NhcnRlcyBjb21wYXJlIGxhIHBoaWxvc29waGllIMOgIHVuIGFyYnJlIDogPGVtPsKrIGxlcyByYWNpbmVzIHNvbnQgbGEgbcOpdGFwaHlzaXF1ZSwgbGUgdHJvbmMgZXN0IGxhIHBoeXNpcXVlLCBldCBsZXMgYnJhbmNoZXMgc29udCBsYSBtw6lkZWNpbmUsIGxhIG3DqWNhbmlxdWUgZXQgbGEgbW9yYWxlIMK7PC9lbT4uIEVsbGUgZW5nbG9iZSBsJ0hvbW1lLCBsZSBNb25kZSBldCBsZXMgU2NpZW5jZXMuPC9wPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPGg0IGNsYXNzPSJmb250LWJvbGQgdGV4dC1uYXZ5LTkwMCB0ZXh0LWxnIG1iLTIiPjIuIExlcyBtw6l0aG9kZXMgcGhpbG9zb3BoaXF1ZXM8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHVsIGNsYXNzPSJsaXN0LWRpc2MgcGwtNSBzcGFjZS15LTIiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxsaT48c3Ryb25nPkxhIG3DqXRob2RlIHLDqWZsZXhpdmUgKE1hw69ldXRpcXVlKSA6PC9zdHJvbmc+IFByZW5kcmUgZHUgcmVjdWwgKMKrIMOqdHJlIGRlaG9ycyBkZSBzb2kgwrspIHBvdXIganVnZXIgc2VzIHByb3ByZXMgY29ubmFpc3NhbmNlcy48L2xpPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxsaT48c3Ryb25nPkxlIHF1ZXN0aW9ubmVtZW50IDo8L3N0cm9uZz4gwqsgRW4gcGhpbG9zb3BoaWUsIGxlcyBxdWVzdGlvbnMgc29udCBwbHVzIGVzc2VudGllbGxlcyBxdWUgbGVzIHLDqXBvbnNlcyDCuyAoS2FybCBKYXNwZXJzKS48L2xpPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxsaT48c3Ryb25nPkxlIGRvdXRlIG3DqXRob2RpcXVlIChEZXNjYXJ0ZXMpIDo8L3N0cm9uZz4gw4AgZGlzdGluZ3VlciBkdSBkb3V0ZSBzY2VwdGlxdWUgYWJzb2x1IGRlIFB5cnJob24uIExlIGRvdXRlIGNhcnTDqXNpZW4gZXN0IHByb3Zpc29pcmUgZXQgbcOobmUgw6AgbGEgY2VydGl0dWRlIHByZW1pw6hyZSA6IDxlbT7CqyBKZSBkb3V0ZSBkb25jIGplIHBlbnNlLCBqZSBwZW5zZSBkb25jIGplIHN1aXMgwrs8L2VtPiAoQ29naXRvKS48L2xpPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC91bD4KICAgICAgICAgICAgICAgICAgICAgICAg', 'base64'), 'UTF8')),
    ('t1c4', 'them1', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+MS4gTGVzIDUgcGlsaWVycyBkZSBsJ2VzcHJpdCBwaGlsb3NvcGhpcXVlPC9oND4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxwIGNsYXNzPSJtYi0yIj5MJzxzdHJvbmc+w6l0b25uZW1lbnQ8L3N0cm9uZz4gKMKrIExhIHBoaWxvc29waGllIGVzdCBmaWxsZSBkJ8OpdG9ubmVtZW50IMK7LCBBcmlzdG90ZSksIGwnPHN0cm9uZz5lc3ByaXQgZGUgZG91dGU8L3N0cm9uZz4sIGwnPHN0cm9uZz5lc3ByaXQgY3JpdGlxdWU8L3N0cm9uZz4gKGp1Z2VyIHBvdXIgdHJvdXZlciBsZSB2cmFpLCBjb250cmFpcmVtZW50IMOgIGwnZXNwcml0IGRlIGNyaXRpcXVlIHF1aSByw6lmdXRlIHN5c3TDqW1hdGlxdWVtZW50KSwgbCc8c3Ryb25nPmVzcHJpdCBkZSB2w6lyaXTDqTwvc3Ryb25nPiBldCBsJzxzdHJvbmc+ZXNwcml0IGRlIHNhZ2Vzc2U8L3N0cm9uZz4uPC9wPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPGg0IGNsYXNzPSJmb250LWJvbGQgdGV4dC1uYXZ5LTkwMCB0ZXh0LWxnIG1iLTIiPjIuIENyaXRpcXVlcyBldCBuw6ljZXNzaXTDqTwvaDQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8cD5Dcml0aXF1w6llIHBvdXIgc29uIGNhcmFjdMOocmUganVnw6kgc3DDqWN1bGF0aWYgb3UgYWJzdHJhaXQgKE1hcnggOiA8ZW0+wqsgTGVzIHBoaWxvc29waGVzIG4nb250IGZhaXQgcXUnaW50ZXJwcsOpdGVyIGxlIG1vbmRlLCBsJ2Vzc2VudGllbCBlc3QgZGUgbGUgdHJhbnNmb3JtZXIgwrs8L2VtPiksIGxhIHBoaWxvc29waGllIGRlbWV1cmUgaW5jb250b3VybmFibGUgOiA8ZW0+wqsgT24gbmUgcGV1dCBwYXMgbmUgcGFzIHBoaWxvc29waGVyIMK7PC9lbT4gKEFyaXN0b3RlIC8gSmFzcGVycykuPC9wPgogICAgICAgICAgICAgICAgICAgICAgICA=', 'base64'), 'UTF8')),
    ('t2c1', 'them2', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+MS4gRMOpZmluaXRpb25zIGZvbmRhbWVudGFsZXM8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHAgY2xhc3M9Im1iLTMiPkxhIDxzdHJvbmc+bmF0dXJlPC9zdHJvbmc+ICg8ZW0+bmF0dXMvbmFzY2k8L2VtPikgZMOpc2lnbmUgY2UgcXVpIGVzdCBpbm7DqSwgY2UgcXVpIGV4aXN0ZSBpbmTDqXBlbmRhbW1lbnQgZGUgbCdhY3Rpb24gaHVtYWluZS4gTGEgPHN0cm9uZz5jdWx0dXJlPC9zdHJvbmc+IGVzdCBsJ2FjdGUgZGUgdHJhbnNmb3JtYXRpb24gZGUgbGEgdGVycmUgKGFncmljdWx0dXJlKSBldCBkZSBsJ2VzcHJpdCAow6lkdWNhdGlvbikuIExhIDxzdHJvbmc+Y2l2aWxpc2F0aW9uPC9zdHJvbmc+IGVzdCBsZSByw6lzdWx0YXQgw6lsYWJvcsOpIGRlcyB0cmFuc2Zvcm1hdGlvbnMgdGVjaG5pcXVlcywgc29jaWFsZXMgZXQgY3VsdHVyZWxsZXMuPC9wPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPGg0IGNsYXNzPSJmb250LWJvbGQgdGV4dC1uYXZ5LTkwMCB0ZXh0LWxnIG1iLTIiPjIuIEh1bWFuaXNhdGlvbiBldCBTb2Npw6l0w6k8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHA+UG91ciBBcmlzdG90ZSwgbCdob21tZSBlc3QgdW4gPGVtPsKrIGFuaW1hbCBwb2xpdGlxdWUgwrs8L2VtPi4gU2Vsb24gQ2xhdWRlIEzDqXZpLVN0cmF1c3MsIGxhIHByb2hpYml0aW9uIGRlIGwnaW5jZXN0ZSBtYXJxdWUgbGUgcGFzc2FnZSB1bml2ZXJzZWwgZGUgbGEgbmF0dXJlIMOgIGxhIGN1bHR1cmUuIEthbnQgc291bGlnbmUgcXVlIGwnw6lkdWNhdGlvbiA8ZW0+wqsgYXJyYWNoZSBsJ2hvbW1lIMOgIHNlcyBwZW5jaGFudHMgYnJ1dGF1eCDCuzwvZW0+IHBhciBsYSBkaXNjaXBsaW5lIGV0IGwnaW5zdHJ1Y3Rpb24uPC9wPgogICAgICAgICAgICAgICAgICAgICAgICA=', 'base64'), 'UTF8')),
    ('t2c2', 'them2', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+TGVzIHRyb2lzIGdyYW5kZXMgY29uY2VwdGlvbnMgcGhpbG9zb3BoaXF1ZXM8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHVsIGNsYXNzPSJsaXN0LWRpc2MgcGwtNSBzcGFjZS15LTIiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxsaT48c3Ryb25nPlBsYXRvbiAoRHVhbGlzbWUgcmFkaWNhbCkgOjwvc3Ryb25nPiBMJ8OibWUgZXN0IGltbWF0w6lyaWVsbGUgZXQgaW1tb3J0ZWxsZSA7IGxlIGNvcnBzIGVzdCB1bmUgwqsgcHJpc29uIMK7ICg8ZW0+c8O0bWEtc8OqbWE8L2VtPikgcXVpIGVudHJhdmUgbCdhY2PDqHMgYXV4IElkw6llcyBwYXIgc2VzIHBhc3Npb25zLjwvbGk+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPGxpPjxzdHJvbmc+QXJpc3RvdGUgKEh5bMOpbW9ycGhpc21lKSA6PC9zdHJvbmc+IEwnaG9tbWUgZXN0IGwndW5pdMOpIGluZGlzc29jaWFibGUgZGUgbGEgbWF0acOocmUgKGNvcnBzKSBldCBkZSBsYSBmb3JtZSAow6JtZSwgcHJpbmNpcGUgdml0YWwgZXQgaW50ZWxsZWN0aWYpLjwvbGk+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPGxpPjxzdHJvbmc+RGVzY2FydGVzIChEdWFsaXNtZSBzdWJzdGFudGllbCkgOjwvc3Ryb25nPiBMJ8OibWUgKHN1YnN0YW5jZSBwZW5zYW50ZSkgZXQgbGUgY29ycHMgKHN1YnN0YW5jZSDDqXRlbmR1ZSkgc29udCBkaXN0aW5jdHMgbWFpcyDDqXRyb2l0ZW1lbnQgdW5pcyBldCBpbnRlcmFnaXNzZW50IHLDqWNpcHJvcXVlbWVudC48L2xpPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC91bD4KICAgICAgICAgICAgICAgICAgICAgICAg', 'base64'), 'UTF8')),
    ('t2c3', 'them2', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+MS4gRMOpc2lyIGNvbW1lIG1hbnF1ZSB2cyBEw6lzaXIgY29tbWUgcHVpc3NhbmNlPC9oND4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxwIGNsYXNzPSJtYi0zIj5Qb3VyIDxzdHJvbmc+UGxhdG9uPC9zdHJvbmc+IChteXRoZSBkZSBsJ2FuZHJvZ3luZSksIGxlIGTDqXNpciBuYcOudCBkJ3VuIG1hbnF1ZSBldCBkJ3VuZSBpbmNvbXBsw6l0dWRlLiDDgCBsJ2ludmVyc2UsIHBvdXIgPHN0cm9uZz5TcGlub3phPC9zdHJvbmc+LCA8ZW0+wqsgbGUgZMOpc2lyIGVzdCBsJ2Vzc2VuY2UgbcOqbWUgZGUgbCdob21tZSDCuzwvZW0+IDogdW5lIHB1aXNzYW5jZSBwb3NpdGl2ZSBkJ2FmZmlybWF0aW9uIGRlIHNvaS48L3A+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+Mi4gTGEgY2xhc3NpZmljYXRpb24gZGVzIGTDqXNpcnMgY2hleiDDiXBpY3VyZTwvaDQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8cD7DiXBpY3VyZSBkaXN0aW5ndWUgbGVzIGTDqXNpcnMgPHN0cm9uZz5uYXR1cmVscyBldCBuw6ljZXNzYWlyZXM8L3N0cm9uZz4gKGJvaXJlLCBtYW5nZXIgc2ltcGxlbWVudCksIGxlcyBkw6lzaXJzIDxzdHJvbmc+bmF0dXJlbHMgZXQgbm9uIG7DqWNlc3NhaXJlczwvc3Ryb25nPiAobWV0cyByYWZmaW7DqXMpIGV0IGxlcyBkw6lzaXJzIDxzdHJvbmc+dmFpbnM8L3N0cm9uZz4gKHJpY2hlc3NlLCBnbG9pcmUpIHF1J2lsIGZhdXQgw6ljYXJ0ZXIgcG91ciBhdHRlaW5kcmUgbCdhdGFyYXhpZS48L3A+CiAgICAgICAgICAgICAgICAgICAgICAgIA==', 'base64'), 'UTF8')),
    ('t2c4', 'them2', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+MS4gTGUgcHJvcHJlIGRlIGwnaG9tbWU8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHAgY2xhc3M9Im1iLTMiPkNvbnRyYWlyZW1lbnQgYXV4IHNpZ25hdXggYW5pbWF1eCBsacOpcyBhdXggYmVzb2lucyBiaW9sb2dpcXVlcywgbGUgbGFuZ2FnZSBodW1haW4gZXN0IHN5bWJvbGlxdWUgZXQgYXJ0aWN1bMOpIChCZW52ZW5pc3RlLCBEZXNjYXJ0ZXMpLiBTYXVzc3VyZSBkaXN0aW5ndWUgbGEgPGVtPmxhbmd1ZTwvZW0+IChpbnN0aXR1dGlvbiBzb2NpYWxlKSBkZSBsYSA8ZW0+cGFyb2xlPC9lbT4gKGFjdGUgaW5kaXZpZHVlbCkuPC9wPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPGg0IGNsYXNzPSJmb250LWJvbGQgdGV4dC1uYXZ5LTkwMCB0ZXh0LWxnIG1iLTIiPjIuIFBvdXZvaXJzIGV0IGxpbWl0ZXM8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHA+Tm9tbWVyIGxlcyBjaG9zZXMgcGVybWV0IGRlIG1hw650cmlzZXIgbGUgbW9uZGUsIG1haXMgbGUgbGFuZ2FnZSBwZXV0IGF1c3NpIHRyb21wZXIgKHJow6l0b3JpcXVlIGRlcyBTb3BoaXN0ZXMpIG91IGRvbWluZXIuIFBvdXIgPHN0cm9uZz5XaXR0Z2Vuc3RlaW48L3N0cm9uZz4sIDxlbT7CqyBsZXMgbGltaXRlcyBkZSBtb24gbGFuZ2FnZSBzaWduaWZpZW50IGxlcyBsaW1pdGVzIGRlIG1vbiBwcm9wcmUgbW9uZGUgwrs8L2VtPiBldCA8ZW0+wqsgc3VyIGNlIGRvbnQgb24gbmUgcGV1dCBwYXJsZXIsIGlsIGZhdXQgbGUgdGFpcmUgwrs8L2VtPi48L3A+CiAgICAgICAgICAgICAgICAgICAgICAgIA==', 'base64'), 'UTF8')),
    ('t3c1', 'them3', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+MS4gRXhpc3RlciBwb3VyIHVuIHN1amV0IGNvbnNjaWVudDwvaDQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8cCBjbGFzcz0ibWItMyI+TGVzIGNob3NlcyBkZSBsYSBuYXR1cmUgc29udCBzaW1wbGVtZW50IGzDoCA7IGwnaG9tbWUsIGx1aSwgPHN0cm9uZz5leGlzdGU8L3N0cm9uZz4gOiBpbCBhIGNvbnNjaWVuY2UgZGUgc29uIMOqdHJlLCBzZSBwcm9qZXR0ZSBkYW5zIGwnYXZlbmlyIGV0IHMnaW50ZXJyb2dlIHN1ciBsZSBzZW5zIGRlIHNhIHZpZS48L3A+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+Mi4gQ29udGluZ2VuY2UgZXQgVGVtcG9yYWxpdMOpPC9oND4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxwPkVzdCA8c3Ryb25nPmNvbnRpbmdlbnQ8L3N0cm9uZz4gY2UgcXVpIHBldXQgw6p0cmUgb3UgbmUgcGFzIMOqdHJlLiBMaXZyw6kgYXUgdGVtcHMgZXQgw6AgbCdob3Jpem9uIGRlIGxhIG1vcnQsIGwnaG9tbWUgw6lwcm91dmUgc2EgZmluaXR1ZGUuPC9wPgogICAgICAgICAgICAgICAgICAgICAgICA=', 'base64'), 'UTF8')),
    ('t3c2', 'them3', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+QW5nb2lzc2UgZXQgRGl2ZXJ0aXNzZW1lbnQ8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHA+RmFjZSDDoCBsYSBjb25zY2llbmNlIGRlIHNhIG1vcnRhbGl0w6kgZXQgZGUgc2EgbWlzw6hyZSBzYW5zIERpZXUsIDxzdHJvbmc+QmxhaXNlIFBhc2NhbDwvc3Ryb25nPiBtb250cmUgcXVlIGwnaG9tbWUgZnVpdCBzYSBjb25kaXRpb24gcGFyIGxlIDxzdHJvbmc+ZGl2ZXJ0aXNzZW1lbnQ8L3N0cm9uZz4gKGpldXgsIG9jY3VwYXRpb25zIHNvY2lhbGVzKSBhZmluIGRlIG5lIHBhcyBwZW5zZXIgw6Agc2EgZmluaXR1ZGUuPC9wPgogICAgICAgICAgICAgICAgICAgICAgICA=', 'base64'), 'UTF8')),
    ('t3c3', 'them3', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+TCdodW1hbmlzbWUgZXhpc3RlbnRpYWxpc3RlIGRlIEplYW4tUGF1bCBTYXJ0cmU8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHAgY2xhc3M9Im1iLTMiPkNoZXogbCdob21tZSwgPHN0cm9uZz7CqyBsJ2V4aXN0ZW5jZSBwcsOpY8OoZGUgbCdlc3NlbmNlIMK7PC9zdHJvbmc+IDogaWwgc3VyZ2l0IGQnYWJvcmQgZGFucyBsZSBtb25kZSBldCBzZSBkw6lmaW5pdCBlbnN1aXRlIHBhciBzZXMgYWN0ZXMuIDxlbT7CqyBMJ2hvbW1lIGVzdCBjb25kYW1uw6kgw6Agw6p0cmUgbGlicmUgwrs8L2VtPiA6IGlsIG5lIHBldXQgcydhYnJpdGVyIGRlcnJpw6hyZSBhdWN1bmUgZXhjdXNlIChkw6l0ZXJtaW5pc21lIG91IG5hdHVyZSBodW1haW5lKSBldCBlbmdhZ2UgbCdodW1hbml0w6kgZW50acOocmUgZGFucyBjaGFjdW4gZGUgc2VzIGNob2l4LjwvcD4KICAgICAgICAgICAgICAgICAgICAgICAg', 'base64'), 'UTF8')),
    ('t4c1', 'them4', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+U2Vuc2F0aW9uLCBQZXJjZXB0aW9uIGV0IFJhaXNvbjwvaDQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8cCBjbGFzcz0ibWItMyI+TGEgPHN0cm9uZz5zZW5zYXRpb248L3N0cm9uZz4gZXN0IHBhc3NpdmUgZXQgaW1tw6lkaWF0ZSAobGVzIGltcHJlc3Npb25zIHNlbG9uIEh1bWUpLiBMYSA8c3Ryb25nPnBlcmNlcHRpb248L3N0cm9uZz4gZXN0IGFjdGl2ZSA6IGVsbGUgb3JnYW5pc2UgbGVzIGRvbm7DqWVzIHNlbnNpYmxlcyBwYXIgbGUganVnZW1lbnQgZGUgbCdlc3ByaXQgKEFsYWluIDogPGVtPsKrIFF1J2VzdC1jZSBxdWUgYmllbiBwZXJjZXZvaXIgc2kgY2Ugbidlc3QgYmllbiBwZW5zZXIgPyDCuzwvZW0+KS48L3A+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8cD5MYSByYWlzb24gY29uc3RydWl0IGxlIHNhdm9pciBwYXIgdHJvaXMgb3DDqXJhdGlvbnMgOiBsZSA8c3Ryb25nPmNvbmNlcHQ8L3N0cm9uZz4sIGxlIDxzdHJvbmc+anVnZW1lbnQ8L3N0cm9uZz4gZXQgbGUgPHN0cm9uZz5yYWlzb25uZW1lbnQ8L3N0cm9uZz4uPC9wPgogICAgICAgICAgICAgICAgICAgICAgICA=', 'base64'), 'UTF8')),
    ('t4c2', 'them4', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+Q29ubmFpc3NhbmNlIHJlbGlnaWV1c2UgZXQgcsOpZmxleGlvbiBwaGlsb3NvcGhpcXVlPC9oND4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxwPkxhIHJlbGlnaW9uICg8ZW0+cmVsaWdhcmU8L2VtPiA6IHJlbGllciwgcmFzc2VtYmxlcikgcmVwb3NlIHN1ciBsYSBmb2kgZXQgbGUgZG9nbWUgKHbDqXJpdMOpIHLDqXbDqWzDqWUgaW5kaXNjdXRhYmxlKS4gVGFuZGlzIHF1ZSBTYWludCBUaG9tYXMgZCdBcXVpbiBjaGVyY2hlIGwnYWNjb3JkIGVudHJlIGZvaSBldCByYWlzb24sIGxlcyBwaGlsb3NvcGhlcyBkZXMgTHVtacOocmVzIGV0IEthcmwgTWFyeCAoPGVtPsKrIExhIHJlbGlnaW9uIGVzdCBsJ29waXVtIGR1IHBldXBsZSDCuzwvZW0+KSBjcml0aXF1ZW50IGxhIHNvdW1pc3Npb24gZG9nbWF0aXF1ZS48L3A+CiAgICAgICAgICAgICAgICAgICAgICAgIA==', 'base64'), 'UTF8')),
    ('t4c3', 'them4', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+RHUgcHLDqWp1Z8OpIMOgIGxhIGTDqW1vbnN0cmF0aW9uPC9oND4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxwPkwnPHN0cm9uZz5vcGluaW9uPC9zdHJvbmc+ICg8ZW0+ZG94YTwvZW0+KSBlc3QgdW5lIGFmZmlybWF0aW9uIG5vbiBmb25kw6llLCBzb3V2ZW50IGlzc3VlIGRlcyBwcsOpanVnw6lzIG91IGRlIGxhIGNvdXR1bWUuIExhIDxzdHJvbmc+dsOpcml0w6k8L3N0cm9uZz4gc2UgZMOpZmluaXQgY2xhc3NpcXVlbWVudCBjb21tZSBsJ2Fkw6lxdWF0aW9uIGRlIGwnZXNwcml0IGV0IGR1IHLDqWVsLCBleGlnZWFudCB1bmUgZMOpbW9uc3RyYXRpb24gcmF0aW9ubmVsbGUgb3UgdW5lIHByZXV2ZSBleHDDqXJpbWVudGFsZS48L3A+CiAgICAgICAgICAgICAgICAgICAgICAgIA==', 'base64'), 'UTF8')),
    ('t4c4', 'them4', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+MS4gTGEgbcOpdGhvZGUgZXhww6lyaW1lbnRhbGUgKE9IRVJJQyAvIERJUEhURVJJQyk8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHAgY2xhc3M9Im1iLTMiPkNsYXVkZSBCZXJuYXJkIMOpdGFibGl0IGxlcyB0cm9pcyB0ZW1wcyBkZSBsYSBkw6ltYXJjaGUgOiA8c3Ryb25nPk9ic2VydmF0aW9uPC9zdHJvbmc+IGRlcyBmYWl0cywgw6ltaXNzaW9uIGQndW5lIDxzdHJvbmc+SHlwb3Row6hzZTwvc3Ryb25nPiAoYW50aWNpcGF0aW9uIHJhdGlvbm5lbGxlKSBldCA8c3Ryb25nPkV4cMOpcmltZW50YXRpb248L3N0cm9uZz4gcG91ciB2w6lyaWZpZXIgZXQgZMOpZ2FnZXIgdW5lIGxvaS48L3A+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+Mi4gw4lwaXN0w6ltb2xvZ2llIGV0IMOJdGhpcXVlPC9oND4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxwPkthcmwgUG9wcGVyIG1vbnRyZSBxdSd1bmUgdGjDqW9yaWUgbidlc3Qgc2NpZW50aWZpcXVlIHF1ZSBzaSBlbGxlIGVzdCA8c3Ryb25nPnLDqWZ1dGFibGUgKGZhbHNpZmlhYmxlKTwvc3Ryb25nPi4gRmFjZSBhdXggZGFuZ2VycyBkZSBsYSB0ZWNobm9zY2llbmNlIChhcm1lcyBudWNsw6lhaXJlcywgYmlvw6l0aGlxdWUpLCBsYSBwaGlsb3NvcGhpZSByYXBwZWxsZSBhdmVjIFJhYmVsYWlzIHF1ZSA8ZW0+wqsgc2NpZW5jZSBzYW5zIGNvbnNjaWVuY2Ugbidlc3QgcXVlIHJ1aW5lIGRlIGwnw6JtZSDCuzwvZW0+LjwvcD4KICAgICAgICAgICAgICAgICAgICAgICAg', 'base64'), 'UTF8')),
    ('t4c5', 'them4', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+TCfFk3V2cmUgZCdhcnQgZXQgbGUganVnZW1lbnQgZXN0aMOpdGlxdWU8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHA+Q29udHJhaXJlbWVudCDDoCBsJ2FydGlzYW4gcXVpIGFwcGxpcXVlIGRlcyByw6hnbGVzIHRlY2huaXF1ZXMgcG91ciBwcm9kdWlyZSB1biBvYmpldCB1dGlsZSwgbCdhcnRpc3RlIGNyw6llIHVuZSDFk3V2cmUgZMOpc2ludMOpcmVzc8OpZS4gUG91ciA8c3Ryb25nPkthbnQ8L3N0cm9uZz4sIGxlIGfDqW5pZSBlc3QgbGEgZGlzcG9zaXRpb24gaW5uw6llIHBhciBsYXF1ZWxsZSBsYSBuYXR1cmUgZG9ubmUgc2VzIHLDqGdsZXMgw6AgbCdhcnQsIGV0IDxlbT7CqyBsZSBiZWF1IGVzdCBjZSBxdWkgcGxhw650IHVuaXZlcnNlbGxlbWVudCBzYW5zIGNvbmNlcHQgwrs8L2VtPi48L3A+CiAgICAgICAgICAgICAgICAgICAgICAgIA==', 'base64'), 'UTF8')),
    ('t5c1', 'them5', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+TGVzIGdyYW5kZXMgZG9jdHJpbmVzIG1vcmFsZXM8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHVsIGNsYXNzPSJsaXN0LWRpc2MgcGwtNSBzcGFjZS15LTIiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxsaT48c3Ryb25nPkxhIG1vcmFsZSBkw6lvbnRvbG9naXF1ZSBkZSBLYW50IDo8L3N0cm9uZz4gRm9uZMOpZSBzdXIgbCdpbnRlbnRpb24gcHVyZSBldCBsZSByZXNwZWN0IGluY29uZGl0aW9ubmVsIGRlIGxhIGxvaSBtb3JhbGUgKGltcMOpcmF0aWYgY2F0w6lnb3JpcXVlKS48L2xpPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxsaT48c3Ryb25nPkwndXRpbGl0YXJpc21lIChCZW50aGFtLCBKLlMuIE1pbGwpIDo8L3N0cm9uZz4gVW5lIGFjdGlvbiBlc3QgbW9yYWxlIHNpIGVsbGUgcHJvY3VyZSBsZSBwbHVzIGdyYW5kIGJvbmhldXIgYXUgcGx1cyBncmFuZCBub21icmUuPC9saT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvdWw+CiAgICAgICAgICAgICAgICAgICAgICAgIA==', 'base64'), 'UTF8')),
    ('t5c2', 'them5', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+TGliZXJ0w6kgZXQgTG9pPC9oND4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxwIGNsYXNzPSJtYi0zIj5MYSBsaWJlcnTDqSBuJ2VzdCBwYXMgbCdhYnNlbmNlIGFuYXJjaGlxdWUgZGUgcsOoZ2xlcy4gU2Vsb24gPHN0cm9uZz5Nb250ZXNxdWlldTwvc3Ryb25nPiwgPGVtPsKrIGxhIGxpYmVydMOpIGVzdCBsZSBkcm9pdCBkZSBmYWlyZSB0b3V0IGNlIHF1ZSBsZXMgbG9pcyBwZXJtZXR0ZW50IMK7PC9lbT4uIFBvdXIgPHN0cm9uZz5Sb3Vzc2VhdTwvc3Ryb25nPiwgPGVtPsKrIGwnb2LDqWlzc2FuY2Ugw6AgbGEgbG9pIHF1J29uIHMnZXN0IHByZXNjcml0ZSBlc3QgbGliZXJ0w6kgwrs8L2VtPi48L3A+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8cD5TZXVsIHVuIMOqdHJlIGxpYnJlIGV0IGRvdMOpIGRlIGNvbnNjaWVuY2UgbW9yYWxlIHBldXQgw6p0cmUgdGVudSBwb3VyIDxzdHJvbmc+cmVzcG9uc2FibGU8L3N0cm9uZz4gKGNpdmlsZW1lbnQsIHDDqW5hbGVtZW50IGV0IG1vcmFsZW1lbnQpIGRlIHNlcyBhY3Rlcy48L3A+CiAgICAgICAgICAgICAgICAgICAgICAgIA==', 'base64'), 'UTF8')),
    ('t5c3', 'them5', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+Rm9uZGVtZW50cyBkdSBEcm9pdCBldCBkZSBsYSBKdXN0aWNlPC9oND4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxwPlJvdXNzZWF1IGTDqW1vbnRyZSBkYW5zIDxlbT5EdSBDb250cmF0IFNvY2lhbDwvZW0+IHF1ZSBsYSBmb3JjZSBuZSBmYWl0IHBhcyBsZSBkcm9pdCA6IHNldWwgdW4gcGFjdGUgZm9uZMOpIHN1ciBsYSB2b2xvbnTDqSBnw6luw6lyYWxlIGZvbmRlIHVuZSBhdXRvcml0w6kgbMOpZ2l0aW1lIGV0IGdhcmFudGl0IGwnw6lnYWxpdMOpIGNpdmlxdWUgZGVzIGNpdG95ZW5zLCBob21tZXMgZXQgZmVtbWVzLjwvcD4KICAgICAgICAgICAgICAgICAgICAgICAg', 'base64'), 'UTF8')),
    ('t5c4', 'them5', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+MS4gTGVzIDMgdHlwZXMgZGUgbMOpZ2l0aW1pdMOpIGR1IHBvdXZvaXIgKE1heCBXZWJlcik8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHAgY2xhc3M9Im1iLTMiPkxlIHBvdXZvaXIgPHN0cm9uZz50cmFkaXRpb25uZWw8L3N0cm9uZz4gKGNvdXR1bWVzKSwgbGUgcG91dm9pciA8c3Ryb25nPmNoYXJpc21hdGlxdWU8L3N0cm9uZz4gKHByZXN0aWdlIGV4Y2VwdGlvbm5lbCBkdSBjaGVmKSBldCBsZSBwb3V2b2lyIDxzdHJvbmc+bMOpZ2FsLXJhdGlvbm5lbDwvc3Ryb25nPiAoZm9uZMOpIHN1ciBsYSBsb2kgZXQgbGVzIGluc3RpdHV0aW9ucykuPC9wPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPGg0IGNsYXNzPSJmb250LWJvbGQgdGV4dC1uYXZ5LTkwMCB0ZXh0LWxnIG1iLTIiPjIuIExlcyBkb2N0cmluZXMgcG9saXRpcXVlczwvaDQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8cD5EZSBsJzxzdHJvbmc+YW5hcmNoaXNtZTwvc3Ryb25nPiAoQmFrb3VuaW5lIDogcmVqZXQgZGUgdG91dCDDiXRhdCkgYXUgPHN0cm9uZz50b3RhbGl0YXJpc21lPC9zdHJvbmc+ICjDiXRhdCBhYnNvbHUpLCBlbiBwYXNzYW50IHBhciBsZSA8c3Ryb25nPmxpYsOpcmFsaXNtZTwvc3Ryb25nPiAoTG9ja2UsIFNtaXRoKSBldCBsYSA8c3Ryb25nPmTDqW1vY3JhdGllPC9zdHJvbmc+IGZvbmTDqWUgc3VyIGxhIHPDqXBhcmF0aW9uIGRlcyBwb3V2b2lycyAoTW9udGVzcXVpZXUpLjwvcD4KICAgICAgICAgICAgICAgICAgICAgICAg', 'base64'), 'UTF8')),
    ('t5c5', 'them5', convert_from(decode('CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+MS4gQW1iaWd1w690w6kgZHUgdHJhdmFpbDwvaDQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8cCBjbGFzcz0ibWItMyI+w4l0eW1vbG9naXF1ZW1lbnQgbGnDqSDDoCBsYSBjb250cmFpbnRlICg8ZW0+dHJpcGFsaXVtPC9lbT4pLCBsZSB0cmF2YWlsIGVzdCBwb3VyIDxzdHJvbmc+SGVnZWw8L3N0cm9uZz4gbGUgbW95ZW4gcGFyIGxlcXVlbCBsJ2hvbW1lIHRyYW5zZm9ybWUgbGEgbmF0dXJlIGV0IHMnw6ltYW5jaXBlIChkaWFsZWN0aXF1ZSBkdSBtYcOudHJlIGV0IGRlIGwnZXNjbGF2ZSkuIFBvdXIgPHN0cm9uZz5LYXJsIE1hcng8L3N0cm9uZz4sIGRhbnMgbGUgc3lzdMOobWUgY2FwaXRhbGlzdGUsIGxlIHRyYXZhaWwgZGV2aWVudCA8c3Ryb25nPmFsacOpbmF0aW9uPC9zdHJvbmc+IGxvcnNxdWUgbCdvdXZyaWVyIGVzdCBkw6lwb3Nzw6lkw6kgZHUgZnJ1aXQgZGUgc29uIGxhYmV1ci48L3A+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8aDQgY2xhc3M9ImZvbnQtYm9sZCB0ZXh0LW5hdnktOTAwIHRleHQtbGcgbWItMiI+Mi4gTCfDqWNoYW5nZSBldCBsYSBzb2Npw6l0w6k8L2g0PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPHA+TCfDqWNoYW5nZSDDqWNvbm9taXF1ZSAoZmFjaWxpdMOpZSBwYXIgbGEgbW9ubmFpZSBzZWxvbiBBcmlzdG90ZSkgZXQgbCfDqWNoYW5nZSBzeW1ib2xpcXVlIChsZSBkb24gZXQgY29udHJlLWRvbiBjaGV6IE1hcmNlbCBNYXVzcykgZm9uZGVudCBsZSBsaWVuIHNvY2lhbC48L3A+CiAgICAgICAgICAgICAgICAgICAgICAgIA==', 'base64'), 'UTF8'))
on conflict (lesson_id) do update set
    source_theme_id = excluded.source_theme_id,
    content_html = excluded.content_html,
    updated_at = now();

-- IMPORTANT : ne pas ajouter de release_at au hasard.
-- Après rapprochement du RAPE concerné avec le calendrier scolaire, insérer une ligne
-- par leçon et par série avec les dates officielles prévues, par exemple :
-- insert into public.course_release_schedule (series, lesson_id, release_at, release_note)
-- values
--   ('Terminale L', 't1c1', 'AAAA-MM-JJ 00:00:00+03', 'Période / séquence selon la répartition'),
--   ('Terminale S', 't1c1', 'AAAA-MM-JJ 00:00:00+03', 'Période / séquence selon la répartition'),
--   ('Terminale OSE', 't1c1', 'AAAA-MM-JJ 00:00:00+03', 'Période / séquence selon la répartition')
-- on conflict (series, lesson_id) do update set
--   release_at = excluded.release_at,
--   release_note = excluded.release_note,
--   updated_at = now();
-- Tant que le calendrier n'a aucune ligne pour une série, aucun contenu de cours
-- de cette série n'est livré, même à un élève dont l'abonnement est actif.
