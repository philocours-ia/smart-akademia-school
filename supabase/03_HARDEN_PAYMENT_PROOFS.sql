-- AKADEMIA — Renforcement de l'intégrité des justificatifs de paiement.
-- À exécuter APRÈS 01_AKADEMIA_supabase_setup.sql et 02_MIGRATION_CONNEXION_ADMIN.sql.
-- Cette migration ne valide jamais un paiement : elle vérifie seulement qu'un fichier
-- existe dans le bucket privé avant d'accepter la demande et protège le justificatif.
-- Aucun mot de passe ni aucune clé secrète n'est utilisé ici.

begin;

-- Une même pièce ne doit pas servir à créer plusieurs demandes d'abonnement.
do $$
begin
    if exists (
        select 1
        from public.subscriptions
        group by proof_path
        having count(*) > 1
    ) then
        raise exception 'Migration interrompue : plusieurs demandes utilisent le même proof_path. Résoudre ces doublons avant de relancer.';
    end if;
end;
$$;

create unique index if not exists subscriptions_proof_path_unique
    on public.subscriptions (proof_path);

-- Vérifie réellement l'existence du fichier dans le bucket privé et son dossier propriétaire.
create or replace function public.assert_akademia_payment_proof_exists()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, storage
as $$
begin
    if new.proof_path is null or btrim(new.proof_path) = '' then
        raise exception 'Une preuve de paiement est obligatoire.';
    end if;

    if split_part(new.proof_path, '/', 1) <> new.user_id::text then
        raise exception 'Le justificatif doit être placé dans le dossier privé du compte connecté.';
    end if;

    if not exists (
        select 1
        from storage.objects o
        where o.bucket_id = 'payment-proofs'
          and o.name = new.proof_path
          and (storage.foldername(o.name))[1] = new.user_id::text
    ) then
        raise exception 'Le fichier de preuve doit être téléversé dans le bucket privé avant la demande.';
    end if;

    return new;
end;
$$;
revoke all on function public.assert_akademia_payment_proof_exists() from public, anon, authenticated;

drop trigger if exists subscriptions_require_existing_payment_proof on public.subscriptions;
create trigger subscriptions_require_existing_payment_proof
before insert on public.subscriptions
for each row execute procedure public.assert_akademia_payment_proof_exists();

-- Les politiques ci-dessous sont aussi déclarées RESTRICTIVE pour qu'une ancienne
-- politique permissive trop large sur storage.objects ne puisse pas ouvrir ce bucket.
drop policy if exists payment_proofs_select_guard on storage.objects;
create policy payment_proofs_select_guard
on storage.objects as restrictive for select to authenticated
using (
    bucket_id <> 'payment-proofs'
    or public.is_admin()
    or (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists payment_proofs_insert_guard on storage.objects;
create policy payment_proofs_insert_guard
on storage.objects as restrictive for insert to authenticated
with check (
    bucket_id <> 'payment-proofs'
    or (storage.foldername(name))[1] = auth.uid()::text
);

-- Un élève peut supprimer un fichier orphelin (par exemple si l'insertion de la demande
-- échoue), mais pas effacer la preuve déjà référencée par une demande d'abonnement.
-- L'administrateur peut supprimer un justificatif depuis le tableau de bord si nécessaire.
drop policy if exists payment_proofs_delete_owner_or_admin on storage.objects;
create policy payment_proofs_delete_owner_or_admin
on storage.objects for delete to authenticated
using (
    bucket_id = 'payment-proofs'
    and (
        public.is_admin()
        or (
            (storage.foldername(name))[1] = auth.uid()::text
            and not exists (
                select 1
                from public.subscriptions s
                where s.user_id = auth.uid()
                  and s.proof_path = storage.objects.name
            )
        )
    )
);

drop policy if exists payment_proofs_delete_guard on storage.objects;
create policy payment_proofs_delete_guard
on storage.objects as restrictive for delete to authenticated
using (
    bucket_id <> 'payment-proofs'
    or public.is_admin()
    or (
        (storage.foldername(name))[1] = auth.uid()::text
        and not exists (
            select 1
            from public.subscriptions s
            where s.user_id = auth.uid()
              and s.proof_path = storage.objects.name
        )
    )
);

commit;
