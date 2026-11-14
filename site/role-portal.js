/* Smart Akademia — portails candidats et professionnels. Les autorisations réelles sont en migration 06 / RLS. */
let pendingCandidateType = '';
const AKADEMIA_SERIES = ['Seconde', 'Première L', 'Première S', 'Première OSE', 'Terminale L', 'Terminale S', 'Terminale OSE'];

function openApplicantSignup(type) {
    if (!['teacher', 'partner', 'promoter'].includes(type)) return;
    if (!supabaseClient) return showToast('Supabase doit être configuré avant de créer un compte candidat.', 'error');
    pendingCandidateType = type;
    const labels = { teacher: 'Candidature enseignant', partner: 'Candidature partenaire', promoter: 'Candidature promoteur' };
    document.getElementById('applicant-signup-type').value = type;
    document.getElementById('applicant-signup-title').textContent = labels[type];
    document.getElementById('auth-screen').classList.add('hidden');
    document.getElementById('applicant-signup-screen').classList.remove('hidden');
    document.getElementById('applicant-signup-screen').scrollIntoView({ behavior: 'instant', block: 'start' });
}

function closeApplicantSignup() {
    document.getElementById('applicant-signup-screen').classList.add('hidden');
    document.getElementById('auth-screen').classList.remove('hidden');
    showAuthPanel('login');
}

async function handleApplicantSignup(e) {
    e.preventDefault();
    if (!supabaseClient) return showToast('Le service Supabase est indisponible.', 'error');
    const type = document.getElementById('applicant-signup-type').value;
    const name = document.getElementById('applicant-signup-name').value.trim();
    const email = document.getElementById('applicant-signup-email').value.trim().toLowerCase();
    const phone = document.getElementById('applicant-signup-phone').value.trim();
    const password = document.getElementById('applicant-signup-password').value;
    const confirm = document.getElementById('applicant-signup-confirm').value;
    if (!['teacher', 'partner', 'promoter'].includes(type)) return showToast('Type de candidature invalide.', 'error');
    if (password.length < 12) return showToast('Le mot de passe doit contenir au moins 12 caractères.', 'error');
    if (password !== confirm) return showToast('Les deux mots de passe ne correspondent pas.', 'error');
    try {
        const { data, error } = await supabaseClient.auth.signUp({
            email, password,
            options: { data: { full_name: name, phone, account_kind: 'applicant', candidate_type: type } }
        });
        if (error) throw error;
        e.target.reset();
        document.getElementById('applicant-signup-screen').classList.add('hidden');
        if (data.session && data.user) {
            const profile = await getCloudProfile(data.user.id);
            await openRolePortal(profile);
            showToast('Compte candidat créé. Complétez maintenant votre dossier de candidature.', 'success');
        } else {
            document.getElementById('auth-screen').classList.remove('hidden');
            showAuthPanel('login');
            showToast('Compte candidat créé. Confirmez votre adresse e-mail, puis connectez-vous avec ce compte pour compléter le dossier.', 'info');
        }
    } catch (error) {
        showToast(error.message || 'Impossible de créer le compte candidat.', 'error');
    }
}

async function openRolePortal(profile) {
    const roles = ['applicant', 'teacher', 'partner', 'promoter'];
    const pendingStudent = profile?.role === 'student' && profile.registrationStatus !== 'approved';
    if (!profile || (!roles.includes(profile.role) && !pendingStudent) || !supabaseClient) {
        if (supabaseClient) await supabaseClient.auth.signOut().catch(() => {});
        return showToast('Le serveur ne confirme pas un rôle professionnel autorisé.', 'error');
    }
    state.currentUser = profile;
    state.isAdmin = false;
    document.body.classList.remove('admin-mode');
    document.getElementById('auth-screen').classList.add('hidden');
    document.getElementById('admin-auth-screen').classList.add('hidden');
    document.getElementById('admin-password-change-screen').classList.add('hidden');
    document.getElementById('app-shell').classList.add('hidden');
    document.getElementById('applicant-signup-screen').classList.add('hidden');
    document.getElementById('role-portal-screen').classList.remove('hidden');
    await renderRolePortal();
}


async function refreshRolePortal() {
    const current = state.currentUser;
    if (!current?.id || !supabaseClient) return showToast('Session Supabase introuvable. Reconnectez-vous.', 'error');
    try {
        const profile = await getCloudProfile(current.id);
        if (profile.role === 'student' && profile.registrationStatus === 'approved') {
            await openAppForStudent(profile);
            showToast('Inscription validée. Votre espace élève est maintenant accessible.', 'success');
            return;
        }
        if (['applicant','teacher','partner','promoter'].includes(profile.role)) {
            state.currentUser = profile;
            if (profile.role !== current.role) showToast('Votre rôle a été mis à jour par l’administration.', 'success');
            await openRolePortal(profile);
            return;
        }
        state.currentUser = profile;
        await renderRolePortal();
    } catch (error) {
        showToast(error.message || 'Impossible de vérifier le dernier statut.', 'error');
    }
}

async function logoutRolePortal() {
    if (supabaseClient) await supabaseClient.auth.signOut().catch(() => {});
    state.currentUser = null;
    state.isAdmin = false;
    document.getElementById('role-portal-screen').classList.add('hidden');
    document.getElementById('role-portal-content').innerHTML = '';
    document.getElementById('auth-screen').classList.remove('hidden');
    showAuthPanel('login');
    showToast('Vous êtes déconnecté de votre espace professionnel.', 'info');
}

function roleBadge(role) {
    return ({ student: 'Validation de l’inscription', applicant: 'Candidat en attente', teacher: 'Enseignant', partner: 'Partenaire', promoter: 'Promoteur' })[role] || role;
}

async function renderRolePortal() {
    const user = state.currentUser;
    if (!user) return;
    document.getElementById('role-portal-title').textContent = roleBadge(user.role);
    document.getElementById('role-portal-subtitle').textContent = `${user.name || user.email} • ${user.email}`;
    const host = document.getElementById('role-portal-content');
    host.innerHTML = '<div class="bg-white rounded-2xl p-6 text-sm text-slate-500">Chargement sécurisé de votre espace…</div>';
    if (user.role === 'student' && user.registrationStatus !== 'approved') return renderStudentEnrollmentWorkspace(host, user);
    if (user.role === 'applicant') return renderApplicantWorkspace(host, user);
    if (user.role === 'teacher') return renderTeacherWorkspace(host, user);
    if (user.role === 'partner') return renderPartnerWorkspace(host, user);
    if (user.role === 'promoter') return renderPromoterWorkspace(host, user);
}

async function renderStudentEnrollmentWorkspace(host, user) {
    let latest = null;
    const { data, error } = await supabaseClient.from('student_enrollment_submissions')
        .select('id,status,amount_ar,payment_method,payment_reference,transaction_reference,created_at,review_note')
        .eq('user_id', user.id).order('created_at', { ascending: false }).limit(1);
    if (error) {
        host.innerHTML = `<div class="bg-amber-50 border border-amber-200 rounded-2xl p-5 text-sm text-amber-900"><strong>Le dossier d’inscription n’est pas encore disponible.</strong><p class="mt-2">La migration 07 doit être appliquée après la migration 06. Détail : ${escapeHtml(error.message || 'table indisponible')}.</p></div>`;
        return;
    }
    latest = data?.[0] || null;
    if (user.registrationStatus === 'pending' && latest?.status === 'pending') {
        host.innerHTML = `<div class="bg-white rounded-2xl p-6 border border-amber-200 space-y-3">
            <span class="inline-flex rounded-full bg-amber-100 text-amber-900 px-3 py-1 text-xs font-bold">Dossier en attente</span>
            <h2 class="font-display text-xl font-bold text-navy-900">Inscription transmise</h2>
            <p class="text-sm text-slate-600">Votre photo d’identité et votre preuve de versement ont été enregistrées. L’administration doit examiner le dossier avant d’autoriser l’accès à l’espace élève.</p>
            <div class="rounded-xl bg-slate-50 p-4 text-xs text-slate-700 space-y-1"><p>Montant : <strong>${Number(latest.amount_ar).toLocaleString('fr-FR')} Ar</strong></p><p>Référence : <strong>${escapeHtml(latest.payment_reference)}</strong></p><p>Transaction : <strong>${escapeHtml(latest.transaction_reference)}</strong></p><p>Déposé le : ${new Date(latest.created_at).toLocaleString('fr-FR')}</p></div>
            ${latest.review_note ? `<p class="text-xs text-slate-600">Note : ${escapeHtml(latest.review_note)}</p>` : ''}
            <button onclick="refreshRolePortal()" class="rounded-xl border px-4 py-2 text-xs font-bold">Actualiser le statut</button>
        </div>`;
        return;
    }
    if (user.registrationStatus === 'rejected' && latest?.status === 'rejected') {
        host.insertAdjacentHTML('beforeend', `<div class="bg-rose-50 border border-rose-200 rounded-xl p-4 text-sm text-rose-900"><strong>Votre dossier précédent a été refusé.</strong>${latest.review_note ? `<p class="mt-1">Motif : ${escapeHtml(latest.review_note)}</p>` : ''}<p class="mt-1 text-xs">Vous pouvez transmettre un nouveau dossier corrigé ci-dessous.</p></div>`);
    }
    host.insertAdjacentHTML('beforeend', `<div class="bg-white rounded-2xl p-5 md:p-7 border border-slate-200 space-y-4">
        <div><p class="text-xs font-bold uppercase tracking-widest text-gold-600">Inscription annuelle</p><h2 class="font-display text-xl font-bold text-navy-900 mt-1">Compléter mon dossier élève</h2><p class="text-sm text-slate-600 mt-2">Compte : ${escapeHtml(user.email)} • ${escapeHtml(user.name || '')} • ${escapeHtml(user.series || '')}</p></div>
        <div class="rounded-xl bg-amber-50 border border-amber-200 p-4 text-xs leading-relaxed text-amber-950"><strong>Droit annuel : 2 000 Ar — MVola uniquement</strong><br>Numéro : <strong>0385528349</strong> • Bénéficiaire : <strong>Nasandratriniaina Julio</strong><br>Référence obligatoire : <strong>AKADEMIA_DROIT</strong><p class="mt-2">Il est préférable d’effectuer la transaction par le numéro fourni dans l’inscription. L’identifiant de transaction et les deux justificatifs sont obligatoires. La vérification faciale/KYC n’est pas activée : aucune donnée biométrique n’est collectée.</p></div>
        <form id="student-enrollment-form" onsubmit="submitStudentEnrollment(event)" class="space-y-3">
            <div><label class="block text-xs font-bold mb-1" for="enrollment-transaction-reference">Référence / identifiant de transaction MVola</label><input id="enrollment-transaction-reference" required minlength="3" maxlength="120" class="auth-input" placeholder="Identifiant figurant sur le reçu"></div>
            <div><label class="block text-xs font-bold mb-1" for="enrollment-identity-photo">Photo d’identité</label><input id="enrollment-identity-photo" type="file" required accept="image/jpeg,image/png,image/webp" class="auth-input"><p class="text-[10px] text-slate-500">JPG, PNG ou WEBP — 10 Mo maximum.</p></div>
            <div><label class="block text-xs font-bold mb-1" for="enrollment-payment-proof">Preuve de paiement MVola</label><input id="enrollment-payment-proof" type="file" required accept="image/jpeg,image/png,image/webp,application/pdf" class="auth-input"><p class="text-[10px] text-slate-500">Image ou PDF — 10 Mo maximum.</p></div>
            <button type="submit" class="rounded-xl bg-navy-900 text-gold-400 px-5 py-3 text-sm font-bold">Envoyer mon dossier pour validation</button>
        </form>
        <p class="text-[11px] text-slate-500">L’envoi d’un dossier ne vaut pas validation du paiement. Les fichiers sont stockés dans un espace privé. L’accès élève reste bloqué jusqu’à décision de l’administrateur.</p>
    </div>`);
}

async function submitStudentEnrollment(e) {
    e.preventDefault();
    const user = state.currentUser;
    if (!user || user.role !== 'student' || !['pending', 'rejected'].includes(user.registrationStatus)) {
        return showToast('Ce dossier ne peut pas être transmis avec le profil actuel.', 'error');
    }
    const transactionReference = document.getElementById('enrollment-transaction-reference').value.trim();
    const identity = document.getElementById('enrollment-identity-photo').files[0];
    const proof = document.getElementById('enrollment-payment-proof').files[0];
    if (transactionReference.length < 3) return showToast('Renseignez l’identifiant de transaction MVola.', 'error');
    let identityPath = null, proofPath = null, dossierSubmitted = false;
    const submit = e.submitter;
    if (submit) { submit.disabled = true; submit.textContent = 'Envoi sécurisé…'; }
    try {
        identityPath = await uploadRoleFile('student-enrollment-documents', user.id, identity, 10*1024*1024, ['image/jpeg','image/png','image/webp']);
        proofPath = await uploadRoleFile('student-enrollment-documents', user.id, proof, 10*1024*1024, ['image/jpeg','image/png','image/webp','application/pdf']);
        const { error } = await supabaseClient.from('student_enrollment_submissions').insert({
            user_id: user.id, amount_ar: 2000, payment_method: 'MVola', payment_reference: 'AKADEMIA_DROIT',
            transaction_reference: transactionReference, identity_photo_path: identityPath, payment_proof_path: proofPath
        });
        if (error) throw error;
        dossierSubmitted = true;
        const profile = await getCloudProfile(user.id);
        state.currentUser = profile;
        showToast('Dossier envoyé. Votre compte reste en attente jusqu’à la validation de l’administration.', 'success');
        await renderRolePortal();
    } catch (error) {
        if (!dossierSubmitted) {
            const cleanup = [];
            if (identityPath) cleanup.push(supabaseClient.storage.from('student-enrollment-documents').remove([identityPath]));
            if (proofPath) cleanup.push(supabaseClient.storage.from('student-enrollment-documents').remove([proofPath]));
            if (cleanup.length) await Promise.allSettled(cleanup);
        }
        showToast(dossierSubmitted ? 'Votre dossier est transmis, mais le statut n’a pas pu être actualisé. Reconnectez-vous ou actualisez le portail.' : (error.message || 'Impossible de transmettre le dossier.'), 'error');
    } finally {
        if (submit) { submit.disabled = false; submit.textContent = 'Envoyer mon dossier pour validation'; }
    }
}

async function renderApplicantWorkspace(host, user) {
    const { data, error } = await supabaseClient.from('role_applications').select('*').eq('user_id', user.id).order('created_at', { ascending: false }).limit(1);
    if (error) {
        host.innerHTML = roleMigrationNotice(error);
        return;
    }
    const application = data?.[0];
    if (application) {
        const statusClass = application.status === 'approved' ? 'emerald' : application.status === 'rejected' ? 'rose' : 'amber';
        host.innerHTML = `<div class="bg-white rounded-2xl p-6 border border-slate-200 space-y-3">
            <p class="text-xs font-bold uppercase tracking-widest text-slate-500">Votre candidature</p>
            <h2 class="font-display text-xl font-bold text-navy-900">${escapeHtml(application.application_type === 'teacher' ? 'Enseignant' : application.application_type === 'partner' ? 'Partenaire' : 'Promoteur')}</h2>
            <span class="inline-block rounded-full px-3 py-1 text-xs font-bold bg-${statusClass}-100 text-${statusClass}-800">${escapeHtml(application.status === 'pending' ? 'En attente de validation' : application.status === 'approved' ? 'Candidature approuvée' : 'Candidature refusée')}</span>
            <p class="text-sm text-slate-600">Déposée le ${new Date(application.created_at).toLocaleString('fr-FR')}.</p>
            ${application.review_note ? `<p class="rounded-xl bg-slate-50 p-3 text-sm text-slate-700">Note de l’administration : ${escapeHtml(application.review_note)}</p>` : ''}
            <p class="text-xs text-slate-500">Une décision est prise par l'administration après examen des informations et pièces transmises. Ne créez pas un second compte pour la même candidature.</p>
            <button onclick="refreshRolePortal()" class="rounded-xl border px-4 py-2 text-xs font-bold">Actualiser le statut</button>
        </div>`;
        return;
    }
    const type = user.requestedRole;
    if (!['teacher', 'partner', 'promoter'].includes(type)) {
        host.innerHTML = '<div class="bg-white rounded-2xl p-6 border border-rose-200 text-sm text-rose-800">Le type de candidature n’est pas configuré sur ce profil. Contactez l’administration.</div>';
        return;
    }
    const label = type === 'teacher' ? 'Candidature enseignant' : type === 'partner' ? 'Candidature partenaire' : 'Candidature promoteur';
    let typeFields = '';
    if (type === 'teacher') {
        typeFields = `<div><label class="block text-xs font-bold mb-1">Spécialité / matière proposée</label><input id="candidate-specialty" required maxlength="120" class="auth-input" placeholder="Intitulé exact figurant dans votre PE de référence"><p class="mt-1 text-[11px] text-slate-500">L’affectation définitive et les séries seront confirmées par l’administrateur à partir des documents PE/RAPE retenus. Aucun catalogue officiel non vérifié n’est présélectionné.</p></div>
        <div><label class="block text-xs font-bold mb-1">Diplôme le plus élevé</label><input id="candidate-diploma-level" required maxlength="120" class="auth-input" placeholder="Intitulé du diplôme"></div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-3"><div><label class="block text-xs font-bold mb-1">Photo d’identité</label><input id="candidate-identity-file" type="file" required accept="image/jpeg,image/png,image/webp" class="auth-input"></div><div><label class="block text-xs font-bold mb-1">Preuve du diplôme</label><input id="candidate-diploma-file" type="file" required accept="image/jpeg,image/png,image/webp,application/pdf" class="auth-input"></div></div>`;
    } else if (type === 'promoter') {
        typeFields = `<div><label class="block text-xs font-bold mb-1">Niveau du diplôme</label><select id="candidate-diploma-level" required class="auth-input"><option value="">Choisir</option><option>Baccalauréat</option><option>Bac+2</option><option>Licence</option><option>Master</option><option>Doctorat</option></select><p class="mt-1 text-[11px] text-slate-500">Niveau minimum requis : Baccalauréat.</p></div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-3"><div><label class="block text-xs font-bold mb-1">Photo d’identité</label><input id="candidate-identity-file" type="file" required accept="image/jpeg,image/png,image/webp" class="auth-input"></div><div><label class="block text-xs font-bold mb-1">Preuve du diplôme</label><input id="candidate-diploma-file" type="file" required accept="image/jpeg,image/png,image/webp,application/pdf" class="auth-input"></div></div>`;
    } else {
        typeFields = `<div><label class="block text-xs font-bold mb-1">Nom du partenaire ou de l’organisme</label><input id="candidate-organization" required maxlength="180" class="auth-input" value="${escapeHtml(user.name || '')}"></div>
        <label class="flex items-start gap-2 text-xs text-slate-700"><input id="candidate-partner-commitment" type="checkbox" required class="mt-0.5"> J’accepte la cotisation mensuelle de 100 000 Ar destinée à la maintenance et au financement des projets de la plateforme, après approbation de ma candidature.</label>
        <div class="rounded-xl bg-amber-50 border border-amber-200 p-3 text-xs text-amber-900">La validation de la candidature ne vaut pas validation d’un paiement. Le justificatif de cotisation et la référence <strong>FINANCEMENT</strong> seront demandés dans l’espace partenaire.</div>`;
    }
    host.innerHTML = `<div class="bg-white rounded-2xl p-5 md:p-7 border border-slate-200 space-y-4">
        <div><p class="text-xs uppercase tracking-widest font-bold text-gold-600">Dossier à compléter</p><h2 class="font-display text-xl font-bold text-navy-900 mt-1">${label}</h2><p class="text-sm text-slate-600 mt-2">Compte : ${escapeHtml(user.email)} • ${escapeHtml(user.phone || 'Téléphone non renseigné')}</p></div>
        <form id="role-application-form" onsubmit="submitRoleApplication(event)" class="space-y-4">
          ${typeFields}
          <div><label class="block text-xs font-bold mb-1">Informations complémentaires (facultatif)</label><textarea id="candidate-extra-note" rows="3" maxlength="2000" class="auth-input" placeholder="Précisions utiles pour l’examen de votre candidature"></textarea></div>
          <button type="submit" class="rounded-xl bg-navy-900 text-gold-400 px-5 py-3 text-sm font-bold">Déposer ma candidature</button>
        </form>
        <p class="text-[11px] text-slate-500">Les pièces sont déposées dans un espace privé. Aucune vérification faciale/KYC n’est activée dans cette version ; aucune donnée biométrique n’est collectée.</p>
    </div>`;
}

function roleMigrationNotice(error) {
    return `<div class="bg-amber-50 border border-amber-200 rounded-2xl p-5 text-sm text-amber-900"><strong>Le module professionnel n’est pas encore installé dans Supabase.</strong><p class="mt-2">Exécutez la migration 06 après les migrations 01, 02, 03 et 05. Détail technique : ${escapeHtml(error?.message || 'tables non disponibles')}.</p></div>`;
}

function validatePrivateFile(file, maxBytes, types) {
    if (!file) throw new Error('Sélectionnez le fichier demandé.');
    if (file.size > maxBytes) throw new Error(`Le fichier ${file.name} dépasse la limite autorisée.`);
    if (!types.includes(file.type)) throw new Error(`Format non autorisé : ${file.name}.`);
}

async function uploadRoleFile(bucket, userId, file, maxBytes, types) {
    validatePrivateFile(file, maxBytes, types);
    const clean = file.name.normalize('NFKD').replace(/[^a-zA-Z0-9._-]+/g, '_').slice(-90);
    const random = (crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`);
    const path = `${userId}/${random}_${clean}`;
    const { error } = await supabaseClient.storage.from(bucket).upload(path, file, { upsert: false, contentType: file.type, cacheControl: '3600' });
    if (error) throw error;
    return path;
}

async function submitRoleApplication(e) {
    e.preventDefault();
    const user = state.currentUser;
    if (!user || user.role !== 'applicant') return showToast('Session candidat invalide.', 'error');
    const type = user.requestedRole;
    try {
        let specialty = null, diplomaLevel = null, organizationName = null, commitment = false;
        const documents = [];
        if (type === 'teacher') {
            specialty = document.getElementById('candidate-specialty').value.trim();
            diplomaLevel = document.getElementById('candidate-diploma-level').value.trim();
            const identity = document.getElementById('candidate-identity-file').files[0];
            const diploma = document.getElementById('candidate-diploma-file').files[0];
            documents.push({ kind: 'identity_photo', path: await uploadRoleFile('role-application-documents', user.id, identity, 10*1024*1024, ['image/jpeg','image/png','image/webp']) });
            documents.push({ kind: 'diploma_proof', path: await uploadRoleFile('role-application-documents', user.id, diploma, 10*1024*1024, ['image/jpeg','image/png','image/webp','application/pdf']) });
        } else if (type === 'promoter') {
            diplomaLevel = document.getElementById('candidate-diploma-level').value;
            if (!['Baccalauréat','Bac+2','Licence','Master','Doctorat'].includes(diplomaLevel)) throw new Error('Le diplôme minimum requis est le Baccalauréat.');
            const identity = document.getElementById('candidate-identity-file').files[0];
            const diploma = document.getElementById('candidate-diploma-file').files[0];
            documents.push({ kind: 'identity_photo', path: await uploadRoleFile('role-application-documents', user.id, identity, 10*1024*1024, ['image/jpeg','image/png','image/webp']) });
            documents.push({ kind: 'diploma_proof', path: await uploadRoleFile('role-application-documents', user.id, diploma, 10*1024*1024, ['image/jpeg','image/png','image/webp','application/pdf']) });
        } else if (type === 'partner') {
            organizationName = document.getElementById('candidate-organization').value.trim();
            commitment = document.getElementById('candidate-partner-commitment').checked;
            if (!commitment) throw new Error('Vous devez accepter la cotisation mensuelle annoncée.');
        } else throw new Error('Type de candidature non valide.');

        const { error } = await supabaseClient.from('role_applications').insert({
            user_id: user.id, application_type: type, applicant_name: user.name || '', applicant_email: user.email,
            phone: user.phone || '', specialty, diploma_level: diplomaLevel, organization_name: organizationName,
            monthly_commitment_accepted: commitment, documents
        });
        if (error) throw error;
        showToast('Candidature déposée. Son statut est maintenant « en attente ».', 'success');
        await renderRolePortal();
    } catch (error) {
        showToast(error.message || 'Impossible de déposer la candidature.', 'error');
    }
}

async function renderTeacherWorkspace(host, user) {
    const [a, w, f, s, r, progressResult, replacementsResult, agendaResult] = await Promise.all([
        supabaseClient.from('teacher_subject_assignments').select('*').eq('teacher_id', user.id).eq('active', true),
        supabaseClient.from('teacher_work_days').select('work_date,note').eq('teacher_id', user.id).order('work_date', { ascending: false }),
        supabaseClient.from('finance_requests').select('*').eq('user_id', user.id).order('created_at', { ascending: false }),
        supabaseClient.from('staff_requests').select('*').eq('teacher_id', user.id).order('created_at', { ascending: false }),
        supabaseClient.from('teacher_resources').select('*').eq('teacher_id', user.id).order('created_at', { ascending: false }),
        supabaseClient.rpc('list_teacher_student_progress'),
        supabaseClient.rpc('list_akademia_replacement_teachers'),
        supabaseClient.from('course_release_schedule').select('series,lesson_id,release_at,release_note').order('release_at', { ascending: true }).limit(100)
    ]);
    const firstError = [a,w,f,s,r,progressResult,replacementsResult,agendaResult].find(x => x.error)?.error;
    if (firstError) { host.innerHTML = roleMigrationNotice(firstError); return; }
    const assignments = a.data || [], workDays = w.data || [], finances = f.data || [], staff = s.data || [], resources = r.data || [], students = progressResult.data || [], replacements = replacementsResult.data || [];
    const assignedSeries = [...new Set(assignments.flatMap(x => x.target_series || []))];
    const agenda = (agendaResult.data || []).filter(x => assignedSeries.includes(x.series));
    const accrued = workDays.length * 6000;
    const reserved = finances.filter(x => ['pending','approved'].includes(x.status)).reduce((sum,x)=>sum+Number(x.amount_ar||0),0);
    const balance = Math.max(0,accrued-reserved);
    const assignmentOptions = assignments.map(x=>`<option value="${escapeHtml(x.subject_name)}">${escapeHtml(x.subject_name)}</option>`).join('');
    const seriesOptions = AKADEMIA_SERIES.map(x=>`<option value="${escapeHtml(x)}">${escapeHtml(x)}</option>`).join('');
    host.innerHTML = `<div class="grid grid-cols-1 md:grid-cols-3 gap-3">
      <div class="bg-white rounded-2xl p-5 border"><p class="text-xs text-slate-500">Journées validées</p><p class="text-2xl font-bold text-navy-900">${workDays.length}</p></div>
      <div class="bg-white rounded-2xl p-5 border"><p class="text-xs text-slate-500">Salaire brut cumulé</p><p class="text-2xl font-bold text-navy-900">${accrued.toLocaleString('fr-FR')} Ar</p><p class="text-[11px] text-slate-500">6 000 Ar par journée validée par l’administration.</p></div>
      <div class="bg-white rounded-2xl p-5 border"><p class="text-xs text-slate-500">Disponible estimé</p><p class="text-2xl font-bold ${balance>=30000?'text-emerald-700':'text-amber-700'}">${balance.toLocaleString('fr-FR')} Ar</p></div>
    </div>
    <div class="bg-white rounded-2xl p-5 border space-y-3"><h2 class="font-bold text-navy-900">Mes affectations</h2>${assignments.length ? assignments.map(x=>`<div class="rounded-xl bg-slate-50 p-3"><p class="font-semibold text-sm">${escapeHtml(x.subject_name)}</p><p class="text-xs text-slate-500">${(x.target_series||[]).map(escapeHtml).join(', ')}</p></div>`).join('') : '<p class="text-sm text-slate-500">Aucune matière ou série n’a encore été affectée par l’administrateur.</p>'}</div>
    <div class="bg-white rounded-2xl p-5 border space-y-3"><h2 class="font-bold text-navy-900">Agenda pédagogique</h2>${agenda.length ? agenda.map(x=>`<div class="flex flex-wrap items-start justify-between gap-2 rounded-xl bg-slate-50 p-3"><div><p class="text-sm font-semibold">${escapeHtml(x.lesson_id)}</p><p class="text-[11px] text-slate-500">${escapeHtml(x.series)} ${x.release_note?`• ${escapeHtml(x.release_note)}`:''}</p></div><p class="text-xs font-bold text-indigo-800">${new Date(x.release_at).toLocaleString('fr-FR')}</p></div>`).join('') : '<p class="text-sm text-slate-500">Aucune date pédagogique validée n’est encore planifiée pour les séries qui vous sont affectées. Les dates apparaîtront après leur saisie par l’administration.</p>'}<p class="text-[10px] text-slate-400">Cet agenda affiche les dates de publication enregistrées dans le calendrier PE/RAPE, pas un emploi du temps horaire de cours.</p></div>
    <div class="bg-white rounded-2xl p-5 border space-y-3"><div class="flex items-center justify-between"><h2 class="font-bold text-navy-900">Suivi de mes élèves</h2><span class="text-xs text-slate-500">Top 3 par leçons terminées</span></div>${students.length?`<div class="grid grid-cols-1 md:grid-cols-3 gap-2">${students.slice(0,3).map((x,i)=>`<div class="rounded-xl bg-indigo-50 p-3"><p class="text-[10px] font-bold text-indigo-700">TOP ${i+1}</p><p class="text-sm font-bold text-navy-900">${escapeHtml(x.full_name||x.email)}</p><p class="text-xs text-slate-600">${escapeHtml(x.series)} • ${Number(x.completed_count)} terminée(s)</p></div>`).join('')}</div><div class="overflow-x-auto"><table class="w-full text-xs"><thead><tr class="text-left border-b"><th class="p-2">Élève</th><th class="p-2">Série</th><th class="p-2">Leçons terminées / suivies</th><th class="p-2">Dernière activité</th></tr></thead><tbody>${students.map(x=>`<tr class="border-b"><td class="p-2">${escapeHtml(x.full_name||x.email)}</td><td class="p-2">${escapeHtml(x.series)}</td><td class="p-2">${Number(x.completed_count)} / ${Number(x.recorded_count)}</td><td class="p-2">${x.last_activity?new Date(x.last_activity).toLocaleDateString('fr-FR'):'Aucune'}</td></tr>`).join('')}</tbody></table></div>`:'<p class="text-sm text-slate-500">Aucun suivi enregistré pour les élèves des séries qui vous sont affectées.</p>'}<p class="text-[10px] text-slate-400">Les nombres correspondent uniquement aux activités enregistrées dans student_progress ; ce n’est pas un taux de progression officiel sur le PE complet.</p></div>
    <div class="grid grid-cols-1 xl:grid-cols-2 gap-5">
      <div class="bg-white rounded-2xl p-5 border space-y-3"><h2 class="font-bold text-navy-900">Finance et réclamations</h2><p class="text-xs text-slate-500">Le calcul dépend exclusivement des journées validées par l’administration (6 000 Ar/jour). La réclamation porte sur le cumul acquis jusqu’au mois choisi, après déduction des demandes déjà réglées ou en attente.</p>
        <form onsubmit="requestTeacherFinance(event,'teacher_salary')" class="flex flex-wrap gap-2"><input id="teacher-pay-month" type="month" required value="${new Date().toISOString().slice(0,7)}" class="auth-input max-w-48"><button class="rounded-xl bg-navy-900 text-gold-400 px-4 py-2 text-xs font-bold">Réclamer le cumul jusqu’à ce mois</button></form>
        <button onclick="requestTeacherFinance(null,'teacher_advance')" ${balance<30000?'disabled':''} class="rounded-xl px-4 py-2 text-xs font-bold ${balance<30000?'bg-slate-100 text-slate-400':'bg-emerald-700 text-white'}">Demande d’avance (seuil 30 000 Ar)</button>
        <div class="space-y-2">${finances.length ? finances.map(x=>`<p class="text-xs rounded-lg bg-slate-50 p-2">${escapeHtml(x.request_type)} — ${Number(x.amount_ar).toLocaleString('fr-FR')} Ar • ${escapeHtml(x.status)} ${x.transfer_reference?`• réf. ${escapeHtml(x.transfer_reference)}`:''}</p>`).join('') : '<p class="text-xs text-slate-400">Aucune demande financière.</p>'}</div>
      </div>
      <div class="bg-white rounded-2xl p-5 border space-y-3"><h2 class="font-bold text-navy-900">Demandes administratives</h2><form onsubmit="submitTeacherStaffRequest(event)" class="space-y-2">
        <select id="staff-request-type" class="auth-input" onchange="updateStaffRequestFields()"><option value="leave">Demande de congé</option><option value="replacement">Demande de remplacement</option><option value="resignation">Démission</option></select>
        <div id="staff-period-wrap" class="grid grid-cols-2 gap-2"><input id="staff-start-date" type="date" class="auth-input"><input id="staff-end-date" type="date" class="auth-input"></div>
        <input id="staff-location" class="auth-input" placeholder="Lieu de jouissance du congé (obligatoire pour un congé)">
        <div id="staff-replacement-wrap"><select id="staff-replacement-teacher" class="auth-input"><option value="">Remplaçant proposé (obligatoire pour un remplacement)</option>${replacements.map(t=>`<option value="${t.teacher_id}">${escapeHtml(t.teacher_name||'Enseignant')}</option>`).join('')}</select></div>
        <textarea id="staff-reason" required maxlength="3000" rows="3" class="auth-input" placeholder="Durée, motif et précisions nécessaires"></textarea>
        <button class="rounded-xl bg-navy-900 text-gold-400 px-4 py-2 text-xs font-bold">Envoyer à l’administration</button>
      </form>${staff.map(x=>`<p class="text-xs bg-slate-50 rounded-lg p-2">${escapeHtml(x.request_type)} • ${escapeHtml(x.status)} • ${new Date(x.created_at).toLocaleDateString('fr-FR')}</p>`).join('')}
      <p class="text-xs font-bold text-rose-700">Toute interruption inopinée de cours implique une coupure de paiement. Songez à avertir l’administrateur.</p></div>
    </div>
    <div class="bg-white rounded-2xl p-5 border space-y-3"><h2 class="font-bold text-navy-900">Gestion de cours et ressources</h2><p class="text-xs text-slate-500">Les ressources sont déposées en PDF/DOC/DOCX et restent non publiées jusqu’à contrôle administratif. Les matières et séries doivent correspondre à vos affectations validées.</p>
      ${assignments.length ? `<form onsubmit="submitTeacherResource(event)" class="grid grid-cols-1 md:grid-cols-2 gap-2">
      <select id="resource-subject" required class="auth-input">${assignmentOptions}</select><input id="resource-title" required maxlength="180" class="auth-input" placeholder="Titre du document">
      <select id="resource-type" class="auth-input"><option value="course">Cours</option><option value="exercise">Exercice</option><option value="evaluation">Évaluation / devoir</option></select>
      <select id="resource-series" multiple required class="auth-input min-h-28">${seriesOptions}</select>
      <input id="resource-due" type="datetime-local" class="auth-input"><input id="resource-file" type="file" accept="application/pdf,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document" required class="auth-input">
      <textarea id="resource-description" rows="2" class="auth-input md:col-span-2" placeholder="Consignes ou description"></textarea><button class="md:col-span-2 rounded-xl bg-navy-900 text-gold-400 px-4 py-3 text-xs font-bold">Déposer la ressource</button></form>` : '<p class="text-sm text-amber-800">L’administrateur doit d’abord affecter une matière.</p>'}
      <div class="space-y-2">${resources.map(x=>`<p class="text-xs rounded-lg p-2 bg-slate-50">${escapeHtml(x.title)} • ${escapeHtml(x.resource_type)} • ${x.published?'Publié':'En attente de publication'}</p>`).join('')}</div>
    </div>
    ${professionalMessagingMarkup()}`;
    updateStaffRequestFields();
    await loadProfessionalMessages();
}

function updateStaffRequestFields() {
    const type = document.getElementById('staff-request-type')?.value;
    const start = document.getElementById('staff-start-date');
    const end = document.getElementById('staff-end-date');
    const location = document.getElementById('staff-location');
    const periodWrap = document.getElementById('staff-period-wrap');
    const replacementWrap = document.getElementById('staff-replacement-wrap');
    const replacement = document.getElementById('staff-replacement-teacher');
    if (!type || !start || !end || !location || !periodWrap || !replacementWrap || !replacement) return;
    const needsPeriod = type === 'leave' || type === 'replacement';
    start.required = needsPeriod;
    end.required = needsPeriod;
    location.required = type === 'leave';
    replacement.required = type === 'replacement';
    periodWrap.classList.toggle('hidden', !needsPeriod);
    replacementWrap.classList.toggle('hidden', type !== 'replacement');
    location.classList.toggle('hidden', type !== 'leave');
    start.max = end.value || '';
    end.min = start.value || '';
}

async function requestTeacherFinance(e, type) {
    if (e?.preventDefault) e.preventDefault();
    try {
        let period = null;
        if (type === 'teacher_salary') {
            const value = document.getElementById('teacher-pay-month').value;
            if (!value) throw new Error('Choisissez un mois.');
            period = `${value}-01`;
        }
        const { data, error } = await supabaseClient.rpc('create_akademia_finance_request', { p_request_type: type, p_period_month: period });
        if (error) throw error;
        showToast('Demande financière enregistrée et transmise à l’administration.', 'success');
        await renderRolePortal();
    } catch (error) { showToast(error.message || 'Demande impossible.', 'error'); }
}

async function submitTeacherStaffRequest(e) {
    e.preventDefault();
    try {
        const type = document.getElementById('staff-request-type').value;
        const startDate = document.getElementById('staff-start-date').value || null;
        const endDate = document.getElementById('staff-end-date').value || null;
        const location = document.getElementById('staff-location').value.trim() || null;
        const replacementTeacher = document.getElementById('staff-replacement-teacher').value || null;
        if (['leave','replacement'].includes(type) && (!startDate || !endDate)) throw new Error('Indiquez les dates de début et de fin.');
        if (startDate && endDate && endDate < startDate) throw new Error('La date de fin doit être postérieure ou égale à la date de début.');
        if (type === 'leave' && !location) throw new Error('Indiquez le lieu de jouissance du congé.');
        if (type === 'replacement' && !replacementTeacher) throw new Error('Choisissez un enseignant remplaçant proposé.');
        const { error } = await supabaseClient.from('staff_requests').insert({
            teacher_id: state.currentUser.id, request_type: type,
            start_date: startDate,
            end_date: endDate,
            location,
            replacement_teacher_id: replacementTeacher,
            reason: document.getElementById('staff-reason').value.trim()
        });
        if (error) throw error;
        showToast('Demande transmise à l’administrateur.', 'success');
        await renderRolePortal();
    } catch (error) { showToast(error.message || 'Demande non envoyée.', 'error'); }
}

async function submitTeacherResource(e) {
    e.preventDefault();
    const user = state.currentUser;
    try {
        const file = document.getElementById('resource-file').files[0];
        const path = await uploadRoleFile('teacher-course-files', user.id, file, 20*1024*1024, ['application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document']);
        const target = [...document.getElementById('resource-series').selectedOptions].map(x=>x.value);
        const dueValue = document.getElementById('resource-due').value;
        const { error } = await supabaseClient.from('teacher_resources').insert({
            teacher_id: user.id, subject_name: document.getElementById('resource-subject').value,
            title: document.getElementById('resource-title').value.trim(), description: document.getElementById('resource-description').value.trim(),
            resource_type: document.getElementById('resource-type').value, target_series: target,
            due_at: dueValue ? new Date(dueValue).toISOString() : null, file_path: path
        });
        if (error) throw error;
        showToast('Ressource déposée. Elle sera publiée après vérification administrative.', 'success');
        await renderRolePortal();
    } catch (error) { showToast(error.message || 'Dépôt de la ressource impossible.', 'error'); }
}

async function renderPartnerWorkspace(host, user) {
    const [m, c] = await Promise.all([
        supabaseClient.from('partner_memberships').select('*').eq('user_id', user.id).maybeSingle(),
        supabaseClient.from('partner_contributions').select('*').eq('user_id', user.id).order('created_at', { ascending: false })
    ]);
    const error = m.error || c.error;
    if (error) { host.innerHTML = roleMigrationNotice(error); return; }
    const membership = m.data;
    const contributions = c.data || [];
    const active = membership && new Date(membership.contribution_expires_at).getTime() > Date.now() && new Date(`${membership.ticket_valid_until}T23:59:59`).getTime() > Date.now();
    host.innerHTML = `<div class="bg-white rounded-2xl border p-5 space-y-3"><h2 class="font-bold text-navy-900">Statut partenaire</h2>
      <p class="text-sm ${active?'text-emerald-700':'text-amber-700'} font-semibold">${active?'Cotisation active':'Aucune cotisation partenaire active'}</p>
      ${membership?`<div class="rounded-xl bg-emerald-50 border border-emerald-200 p-4"><p class="text-xs text-emerald-800">Ticket partenaire à six chiffres (code secondaire, non utilisable à la place de votre mot de passe Supabase)</p><p class="font-mono text-3xl font-bold tracking-[.3em] text-emerald-900 mt-2">${escapeHtml(membership.access_ticket)}</p><p class="text-xs text-emerald-800 mt-2">Valide jusqu’au ${new Date(`${membership.ticket_valid_until}T00:00:00`).toLocaleDateString('fr-FR')} • Cotisation active jusqu’au ${new Date(membership.contribution_expires_at).toLocaleDateString('fr-FR')}</p></div>`:''}
      <p class="text-xs text-slate-500">Le ticket annuel n’est qu’un identifiant de membre. La connexion et les permissions restent protégées par Supabase Auth et les politiques RLS.</p></div>
      <div class="bg-white rounded-2xl border p-5 space-y-3"><h2 class="font-bold text-navy-900">Déclarer la cotisation mensuelle de 100 000 Ar</h2>
        <p class="text-xs text-slate-600">MVola : <strong>0385528349 — Nasandratriniaina Julio</strong> • Binance Pay : <strong>820751129</strong> • Référence obligatoire : <strong>FINANCEMENT</strong>. Le paiement est vérifié manuellement.</p>
        <form onsubmit="submitPartnerContribution(event)" class="grid grid-cols-1 md:grid-cols-2 gap-2">
          <select id="partner-payment-method" class="auth-input"><option>MVola</option><option>Binance Pay</option></select>
          <input id="partner-transaction-reference" required maxlength="120" class="auth-input" placeholder="Référence de transaction">
          <input value="100 000 Ar" readonly class="auth-input bg-slate-50"><input value="FINANCEMENT" readonly class="auth-input bg-slate-50 font-mono">
          <input id="partner-payment-proof" type="file" required accept="image/jpeg,image/png,image/webp,application/pdf" class="auth-input md:col-span-2"><button class="md:col-span-2 rounded-xl bg-navy-900 text-gold-400 px-4 py-3 text-xs font-bold">Envoyer la preuve de cotisation</button>
        </form>
      </div>
      <div class="bg-white rounded-2xl border p-5"><h2 class="font-bold text-navy-900 mb-3">Historique des cotisations</h2>${contributions.length?contributions.map(x=>`<p class="text-xs bg-slate-50 rounded-lg p-2 mb-2">100 000 Ar • ${escapeHtml(x.payment_method)} • ${escapeHtml(x.status)} • ${new Date(x.created_at).toLocaleDateString('fr-FR')}</p>`).join(''):'<p class="text-xs text-slate-500">Aucun paiement soumis.</p>'}</div>
      <div class="bg-white rounded-2xl border p-5 space-y-3"><h2 class="font-bold text-navy-900">Consultation et audit des cours</h2><div id="partner-audit-courses" class="space-y-2"><p class="text-xs text-slate-500">Chargement des ressources disponibles…</p></div></div>
      ${professionalMessagingMarkup()}`;
    if (active) await renderPartnerAuditCourses();
    else document.getElementById('partner-audit-courses').innerHTML='<p class="text-xs text-amber-800">La consultation des cours exige une cotisation mensuelle active et un ticket annuel valide.</p>';
    await loadProfessionalMessages();
}

async function submitPartnerContribution(e) {
    e.preventDefault();
    const user = state.currentUser;
    try {
        const file = document.getElementById('partner-payment-proof').files[0];
        const path = await uploadRoleFile('partner-payment-proofs', user.id, file, 10*1024*1024, ['image/jpeg','image/png','image/webp','application/pdf']);
        const { error } = await supabaseClient.from('partner_contributions').insert({
            user_id: user.id, amount_ar: 100000, payment_method: document.getElementById('partner-payment-method').value,
            payment_reference: 'FINANCEMENT', transaction_reference: document.getElementById('partner-transaction-reference').value.trim(), proof_path: path
        });
        if (error) throw error;
        showToast('Justificatif transmis. Il sera contrôlé par l’administration.', 'success');
        await renderRolePortal();
    } catch (error) { showToast(error.message || 'Impossible de transmettre la cotisation.', 'error'); }
}

async function renderPromoterWorkspace(host, user) {
    const [c, f, referralResult] = await Promise.all([
        supabaseClient.from('promoter_commissions').select('id,student_id,amount_ar,created_at').eq('promoter_id', user.id).order('created_at', { ascending: false }),
        supabaseClient.from('finance_requests').select('*').eq('user_id', user.id).order('created_at', { ascending: false }),
        supabaseClient.rpc('list_akademia_promoter_referrals')
    ]);
    const error = c.error || f.error || referralResult.error;
    if (error) { host.innerHTML = roleMigrationNotice(error); return; }
    const commissions = c.data || [], finances = f.data || [], referrals = referralResult.data || [];
    const gross = commissions.reduce((n,x)=>n+Number(x.amount_ar||0),0);
    const reserved = finances.filter(x=>['pending','approved'].includes(x.status)).reduce((n,x)=>n+Number(x.amount_ar||0),0);
    const balance = Math.max(0,gross-reserved);
    const code = user.referralCode || '';
    const link = code ? `${location.origin}${location.pathname}?ref=${encodeURIComponent(code)}` : '';
    host.innerHTML = `<div class="grid grid-cols-1 md:grid-cols-3 gap-3"><div class="bg-white rounded-2xl border p-5"><p class="text-xs text-slate-500">Élèves validés par votre lien</p><p class="text-2xl font-bold text-navy-900">${commissions.length}</p></div><div class="bg-white rounded-2xl border p-5"><p class="text-xs text-slate-500">Commissions cumulées</p><p class="text-2xl font-bold text-navy-900">${gross.toLocaleString('fr-FR')} Ar</p></div><div class="bg-white rounded-2xl border p-5"><p class="text-xs text-slate-500">Disponible estimé</p><p class="text-2xl font-bold ${balance>=30000?'text-emerald-700':'text-amber-700'}">${balance.toLocaleString('fr-FR')} Ar</p></div></div>
      <div class="bg-white rounded-2xl border p-5 space-y-3"><h2 class="font-bold text-navy-900">Votre code referral</h2><p class="font-mono text-2xl font-bold tracking-widest text-indigo-800">${escapeHtml(code || 'Non attribué')}</p><p class="text-xs text-slate-500">Commission : 1 000 Ar par élève dont l’inscription est approuvée. Le code est associé au compte lors de l’inscription.</p>
      ${link?`<input readonly id="promoter-referral-link" class="auth-input" value="${escapeHtml(link)}"><button onclick="copyPromoterLink()" class="rounded-xl bg-navy-900 text-gold-400 px-4 py-2 text-xs font-bold">Copier mon lien de parrainage</button>`:''}</div>
      <div class="bg-white rounded-2xl border p-5 space-y-3"><h2 class="font-bold text-navy-900">Finance</h2><p class="text-xs text-slate-500">Vous pouvez réclamer le solde à partir de 30 000 Ar.</p><button onclick="requestPromoterPayout()" ${balance<30000?'disabled':''} class="rounded-xl px-4 py-2 text-xs font-bold ${balance<30000?'bg-slate-100 text-slate-400':'bg-emerald-700 text-white'}">Réclamer mon paiement</button>
      ${finances.map(x=>`<p class="text-xs bg-slate-50 p-2 rounded-lg">${Number(x.amount_ar).toLocaleString('fr-FR')} Ar • ${escapeHtml(x.status)} ${x.transfer_reference?`• ${escapeHtml(x.transfer_reference)}`:''}</p>`).join('')}</div>
      <div class="bg-white rounded-2xl border p-5"><h2 class="font-bold text-navy-900 mb-3">Inscrits associés</h2>${referrals.length?referrals.map(x=>`<p class="text-xs bg-slate-50 rounded-lg p-2 mb-2">${escapeHtml(x.student_name||'Élève')} • ${escapeHtml(x.series)} • commission ${Number(x.commission_ar).toLocaleString('fr-FR')} Ar • ${new Date(x.approved_at).toLocaleDateString('fr-FR')}</p>`).join(''):'<p class="text-xs text-slate-500">Aucune inscription validée par votre code.</p>'}</div>
      ${professionalMessagingMarkup()}`;
    await loadProfessionalMessages();
}

async function requestPromoterPayout() {
    try {
        const { error } = await supabaseClient.rpc('create_akademia_finance_request', { p_request_type: 'promoter_payout', p_period_month: null });
        if (error) throw error;
        showToast('Demande de paiement transmise à l’administration.', 'success');
        await renderRolePortal();
    } catch (error) { showToast(error.message || 'Solde insuffisant ou demande impossible.', 'error'); }
}

function copyPromoterLink() {
    const field = document.getElementById('promoter-referral-link');
    if (!field) return;
    field.select();
    if (navigator.clipboard?.writeText) navigator.clipboard.writeText(field.value).then(()=>showToast('Lien copié.', 'success')).catch(()=>showToast('Copiez le lien sélectionné manuellement.', 'info'));
    else showToast('Lien sélectionné : utilisez Copier dans le menu de votre navigateur.', 'info');
}

function professionalMessagingMarkup() {
    return `<div class="bg-white rounded-2xl border p-5 space-y-3"><h2 class="font-bold text-navy-900"><i class="fas fa-envelope text-indigo-600 mr-2"></i>Messagerie professionnelle</h2>
      <form onsubmit="sendProfessionalMessage(event)" class="grid grid-cols-1 md:grid-cols-3 gap-2"><select id="professional-message-recipient" required class="auth-input"><option value="">Contacts autorisés…</option></select><input id="professional-message-subject" required maxlength="160" class="auth-input" placeholder="Objet"><input id="professional-message-body" required maxlength="10000" class="auth-input" placeholder="Votre message"><button class="md:col-span-3 rounded-xl bg-navy-900 text-gold-400 px-4 py-2 text-xs font-bold">Envoyer</button></form>
      <div id="professional-messages-list" class="space-y-2"><p class="text-xs text-slate-400">Chargement…</p></div></div>`;
}

async function loadRoleMessages() {
    if (!supabaseClient || !state.currentUser?.id) return;
    try {
        const { data: contacts, error: contactsError } = await supabaseClient.rpc('list_akademia_message_contacts');
        if (contactsError) throw contactsError;
        const { data: rows, error } = await supabaseClient.from('role_messages').select('*')
            .or(`sender_id.eq.${state.currentUser.id},recipient_id.eq.${state.currentUser.id}`).order('created_at', { ascending: false }).limit(100);
        if (error) throw error;
        const fill = (id) => {
            const select = document.getElementById(id);
            if (!select) return;
            select.innerHTML = '<option value="">Choisir un destinataire</option>' + (contacts||[]).map(c=>`<option value="${c.user_id}">${escapeHtml(c.full_name||c.role)} — ${escapeHtml(c.role)}${c.series?` (${escapeHtml(c.series)})`:''}</option>`).join('');
        };
        fill('role-message-recipient');
        fill('professional-message-recipient');
        const render = (containerId) => {
            const container = document.getElementById(containerId);
            if (!container) return;
            container.innerHTML = (rows||[]).length ? rows.map(m=>{
                const outgoing=m.sender_id===state.currentUser.id;
                const person=(contacts||[]).find(c=>c.user_id===(outgoing?m.recipient_id:m.sender_id));
                return `<div class="rounded-xl border border-slate-200 p-3 ${outgoing?'bg-indigo-50':'bg-slate-50'}"><p class="text-[11px] font-bold text-navy-900">${outgoing?'Envoyé à':'Reçu de'} ${escapeHtml(person?.full_name||'Contact')} • ${new Date(m.created_at).toLocaleString('fr-FR')}</p><p class="text-xs font-semibold mt-1">${escapeHtml(m.subject)}</p><p class="text-sm text-slate-700 mt-1 whitespace-pre-wrap">${escapeHtml(m.body)}</p></div>`;
            }).join('') : '<p class="text-xs text-slate-500">Aucun message pour le moment.</p>';
        };
        render('role-messages-list'); render('professional-messages-list');
    } catch (error) {
        const msg=`Messagerie directe non disponible : ${escapeHtml(error.message||'migration 06 manquante')}`;
        ['role-messages-list','professional-messages-list'].forEach(id=>{const el=document.getElementById(id);if(el)el.innerHTML=`<p class="text-xs text-amber-800">${msg}</p>`;});
    }
}

async function loadProfessionalMessages() { return loadRoleMessages(); }

async function sendRoleMessage(e) { return performRoleMessageSend(e, 'role-message'); }
async function sendProfessionalMessage(e) { return performRoleMessageSend(e, 'professional-message'); }
async function performRoleMessageSend(e, prefix) {
    e.preventDefault();
    const recipient = document.getElementById(`${prefix}-recipient`)?.value;
    const subject = document.getElementById(`${prefix}-subject`)?.value.trim();
    const body = document.getElementById(`${prefix}-body`)?.value.trim();
    if (!recipient) return showToast('Choisissez un destinataire.', 'error');
    try {
        const { error } = await supabaseClient.rpc('send_akademia_message', { p_recipient_id: recipient, p_subject: subject, p_body: body });
        if (error) throw error;
        e.target.reset();
        showToast('Message envoyé.', 'success');
        await loadRoleMessages();
    } catch (error) { showToast(error.message || 'Message non envoyé.', 'error'); }
}


async function renderAdminPromoters(promoters, commissions){
    const el=document.getElementById('admin-promoter-tracking-list');if(!el)return;
    if(!promoters.length){el.innerHTML='<p class="text-xs text-slate-500">Aucun promoteur approuvé pour le moment.</p>';return;}
    const studentIds=[...new Set(commissions.map(x=>x.student_id))];
    let students=[];
    if(studentIds.length){const {data,error}=await supabaseClient.from('profiles').select('id,full_name,email,series,created_at').in('id',studentIds);if(!error)students=data||[];}
    el.innerHTML=promoters.map(p=>{
      const own=commissions.filter(x=>x.promoter_id===p.id);const total=own.reduce((n,x)=>n+Number(x.amount_ar||0),0);
      return `<div class="rounded-xl border p-3"><div class="flex flex-wrap justify-between gap-2"><div><p class="text-sm font-bold">${escapeHtml(p.full_name||p.email)}</p><p class="text-xs text-slate-500">${escapeHtml(p.email)} • code ${escapeHtml(p.referral_code||'non attribué')}</p></div><p class="text-xs font-bold">${own.length} élève(s) • ${total.toLocaleString('fr-FR')} Ar</p></div>
      ${own.length?`<div class="mt-2 space-y-1">${own.map(c=>{const st=students.find(x=>x.id===c.student_id);return `<p class="text-[11px] text-slate-600">${escapeHtml(st?.full_name||st?.email||c.student_id)} • ${escapeHtml(st?.series||'')} • ${c.amount_ar.toLocaleString('fr-FR')} Ar • ${new Date(c.created_at).toLocaleDateString('fr-FR')}</p>`}).join('')}</div>`:'<p class="text-[11px] text-slate-400 mt-2">Aucune inscription approuvée par ce code.</p>'}</div>`;
    }).join('');
}

async function renderPartnerAuditCourses(){
    const host=document.getElementById('partner-audit-courses');if(!host)return;
    try{
      const {data,error}=await supabaseClient.from('course_lesson_content').select('lesson_id,source_theme_id,content_html').order('lesson_id');
      if(error)throw error;
      if(!data?.length){host.innerHTML='<p class="text-xs text-slate-500">Aucun contenu de cours n’est encore publié dans Supabase.</p>';return;}
      host.innerHTML=data.map(row=>{const plain=(row.content_html||'').replace(/<[^>]*>/g,' ').replace(/\s+/g,' ').trim().slice(0,900);return `<details class="rounded-xl border border-slate-200 p-3"><summary class="cursor-pointer text-sm font-semibold text-navy-900">${escapeHtml(row.lesson_id)} • ${escapeHtml(row.source_theme_id)}</summary><p class="text-xs text-slate-700 whitespace-pre-wrap mt-2">${escapeHtml(plain||'Contenu non renseigné.')}</p></details>`}).join('');
    }catch(error){host.innerHTML=`<p class="text-xs text-amber-800">Consultation non disponible : ${escapeHtml(error.message||'vérifiez la migration 06 et les droits partenaire actifs')}.</p>`;}
}

async function loadAdminRoleMessages() {
    if (!state.isAdmin || !supabaseClient) return;
    const recipient = document.getElementById('admin-role-message-recipient');
    const list = document.getElementById('admin-role-messages-list');
    if (!recipient || !list) return;
    try {
        const [contacts, messages] = await Promise.all([
            supabaseClient.rpc('list_akademia_message_contacts'),
            supabaseClient.from('role_messages').select('id,sender_id,recipient_id,subject,body,read_at,created_at').order('created_at',{ascending:false}).limit(50)
        ]);
        if (contacts.error) throw contacts.error;
        if (messages.error) throw messages.error;
        const options = (contacts.data||[]).map(c=>`<option value="${c.user_id}">${escapeHtml(c.full_name||c.user_id)} — ${escapeHtml(c.role)}${c.series?` (${escapeHtml(c.series)})`:''}</option>`).join('');
        recipient.innerHTML = '<option value="">Choisir un destinataire</option>'+options;
        const ids = [...new Set((messages.data||[]).flatMap(m=>[m.sender_id,m.recipient_id]))];
        let names = {};
        if(ids.length){const people=await supabaseClient.from('profiles').select('id,full_name,email,role').in('id',ids);if(!people.error)names=Object.fromEntries((people.data||[]).map(p=>[p.id,`${p.full_name||p.email} (${p.role})`]));}
        list.innerHTML = (messages.data||[]).length ? (messages.data||[]).map(m=>`<div class="rounded-xl border p-3 bg-slate-50"><p class="text-xs font-bold">${escapeHtml(m.subject)}</p><p class="text-[10px] text-slate-500">De : ${escapeHtml(names[m.sender_id]||m.sender_id)} • À : ${escapeHtml(names[m.recipient_id]||m.recipient_id)} • ${new Date(m.created_at).toLocaleString('fr-FR')}</p><p class="text-xs whitespace-pre-wrap mt-2">${escapeHtml(m.body)}</p></div>`).join('') : '<p class="text-xs text-slate-500">Aucun message de la messagerie multi-profils.</p>';
    } catch(error) { list.innerHTML=`<p class="text-xs text-amber-800">Messagerie indisponible. ${escapeHtml(error.message||'Vérifiez la migration 06.')}</p>`; }
}

async function sendAdminRoleMessage(e) {
    e.preventDefault();
    if(!state.isAdmin || !supabaseClient)return;
    try{
        const {error}=await supabaseClient.rpc('send_akademia_message',{
            p_recipient_id:document.getElementById('admin-role-message-recipient').value,
            p_subject:document.getElementById('admin-role-message-subject').value.trim(),
            p_body:document.getElementById('admin-role-message-body').value.trim()
        });
        if(error)throw error;
        document.getElementById('admin-role-message-subject').value='';
        document.getElementById('admin-role-message-body').value='';
        showToast('Message administratif envoyé.','success');
        await loadAdminRoleMessages();
    }catch(error){showToast(error.message||'Message non envoyé.','error');}
}

async function renderRoleAdminLists() {
    if (!state.isAdmin || !supabaseClient) return;
    const ids = ['admin-role-applications-list','admin-partner-contributions-list','admin-finance-requests-list','admin-staff-requests-list','admin-teacher-workday-list','admin-teacher-resources-list','admin-promoter-tracking-list'];
    try {
        const [apps, partners, finance, staff, teachers, resources, promotersResult, commissionsResult] = await Promise.all([
            supabaseClient.from('role_applications').select('*').order('created_at',{ascending:false}),
            supabaseClient.from('partner_contributions').select('*').order('created_at',{ascending:false}),
            supabaseClient.from('finance_requests').select('*').order('created_at',{ascending:false}),
            supabaseClient.from('staff_requests').select('*').order('created_at',{ascending:false}),
            supabaseClient.from('profiles').select('id,full_name,email,series').eq('role','teacher').order('full_name'),
            supabaseClient.from('teacher_resources').select('*').order('created_at',{ascending:false}),
            supabaseClient.from('profiles').select('id,full_name,email,referral_code').eq('role','promoter').order('full_name'),
            supabaseClient.from('promoter_commissions').select('promoter_id,student_id,amount_ar,created_at').order('created_at',{ascending:false})
        ]);
        const error = [apps,partners,finance,staff,teachers,resources,promotersResult,commissionsResult].find(x=>x.error)?.error;
        if(error) throw error;
        await renderAdminApplications(apps.data||[]);
        await renderAdminPartnerContributions(partners.data||[]);
        renderAdminFinanceRequests(finance.data||[]);
        renderAdminStaffRequests(staff.data||[]);
        renderAdminWorkdays(teachers.data||[]);
        await renderAdminTeacherResources(resources.data||[]);
        await renderAdminPromoters(promotersResult.data||[], commissionsResult.data||[]);
    } catch(error) {
        ids.forEach(id=>{const el=document.getElementById(id);if(el)el.innerHTML=`<p class="text-xs text-amber-800">Module non chargé. Vérifiez l’exécution de la migration 06. ${escapeHtml(error.message||'')}</p>`;});
    }
}

async function renderAdminApplications(apps) {
    const el=document.getElementById('admin-role-applications-list'); if(!el)return;
    const pending=apps.filter(x=>x.status==='pending');
    if(!pending.length){el.innerHTML='<p class="text-xs text-slate-500">Aucune candidature professionnelle en attente.</p>';return;}
    const cards=[];
    for(const a of pending){
        const docs=Array.isArray(a.documents)?a.documents:[];
        const links=[];
        for(const d of docs){const {data}=await supabaseClient.storage.from('role-application-documents').createSignedUrl(d.path,900);if(data?.signedUrl)links.push(`<a class="text-xs text-indigo-700 underline mr-3" target="_blank" rel="noopener noreferrer" href="${escapeHtml(data.signedUrl)}">${d.kind==='identity_photo'?'Photo d’identité':'Preuve de diplôme'}</a>`);}
        const assignment=a.application_type==='teacher'?`<div class="mt-3 grid grid-cols-1 md:grid-cols-2 gap-2"><input name="subject" required value="${escapeHtml(a.specialty||'')}" placeholder="Matière à confirmer" class="auth-input"><div class="grid grid-cols-2 gap-1 text-[11px]">${AKADEMIA_SERIES.map(x=>`<label class="flex items-center gap-1"><input type="checkbox" name="series" value="${escapeHtml(x)}">${escapeHtml(x)}</label>`).join('')}</div><p class="md:col-span-2 text-[10px] text-slate-500">Confirmez la spécialité à partir des PE officiels avant l’affectation.</p></div>`:'';
        cards.push(`<div class="rounded-xl border border-slate-200 p-4"><div class="flex flex-wrap justify-between gap-2"><div><p class="font-bold text-sm text-navy-900">${escapeHtml(a.applicant_name)}</p><p class="text-xs text-slate-600">${escapeHtml(a.applicant_email)} • ${escapeHtml(a.phone)} • ${escapeHtml(a.application_type)}</p><p class="text-xs text-slate-500 mt-1">${escapeHtml(a.specialty||a.organization_name||a.diploma_level||'')}</p><div class="mt-2">${links.join('')||'<span class="text-xs text-amber-700">Aucune pièce signée disponible.</span>'}</div></div><span class="text-[11px] text-amber-800">En attente</span></div>
        <form class="mt-3 space-y-2" onsubmit="adminReviewRoleApplication(event,'${a.id}','${a.application_type}')">${assignment}<input name="note" class="auth-input" placeholder="Note interne (facultatif)"><div class="flex gap-2"><button name="decision" value="approved" class="rounded-lg bg-emerald-600 text-white px-3 py-2 text-xs font-bold">Approuver</button><button name="decision" value="rejected" class="rounded-lg bg-rose-600 text-white px-3 py-2 text-xs font-bold">Refuser</button></div></form></div>`);
    }
    el.innerHTML=cards.join('');
}

async function adminReviewRoleApplication(e,id,type){
    e.preventDefault();
    if(!state.isAdmin)return;
    const form=e.target; const decision=e.submitter?.value || 'approved';
    const note=form.elements.note?.value||null;
    let subject=null,series=[];
    if(type==='teacher'&&decision==='approved'){
        subject=form.elements.subject.value.trim();
        series=[...form.querySelectorAll('input[name="series"]:checked')].map(x=>x.value);
        if(!subject||!series.length)return showToast('Confirmez la matière et au moins une série avant d’approuver.', 'error');
    }
    try{
        let result;
        if(type==='teacher'&&decision==='approved'){
            result=await supabaseClient.rpc('admin_finalize_teacher_application',{p_application_id:id,p_review_note:note,p_subject_name:subject,p_target_series:series});
        }else{
            result=await supabaseClient.rpc('admin_review_role_application',{p_application_id:id,p_decision:decision,p_review_note:note});
        }
        if(result.error)throw result.error;
        showToast(decision==='approved'?'Candidature approuvée.':'Candidature refusée.','success');
        await renderAdminLists();
    }catch(error){showToast(error.message||'Décision non enregistrée.','error');}
}

async function renderAdminPartnerContributions(rows){
    const el=document.getElementById('admin-partner-contributions-list');if(!el)return;
    const pending=rows.filter(x=>x.status==='pending');if(!pending.length){el.innerHTML='<p class="text-xs text-slate-500">Aucune cotisation en attente.</p>';return;}
    const parts=[];
    for(const x of pending){const {data:pr}=await supabaseClient.from('profiles').select('full_name,email').eq('id',x.user_id).maybeSingle();const {data}=await supabaseClient.storage.from('partner-payment-proofs').createSignedUrl(x.proof_path,900);
      parts.push(`<div class="rounded-xl border p-3 space-y-2"><p class="text-xs font-bold">${escapeHtml(pr?.full_name||pr?.email||x.user_id)} • 100 000 Ar • ${escapeHtml(x.payment_method)}</p><p class="text-[11px]">Réf. ${escapeHtml(x.payment_reference)} • transaction ${escapeHtml(x.transaction_reference)}</p>${data?.signedUrl?`<a class="text-xs underline text-indigo-700" target="_blank" rel="noopener noreferrer" href="${escapeHtml(data.signedUrl)}">Consulter la preuve</a>`:'<span class="text-xs text-rose-700">Preuve privée indisponible</span>'}
      <form class="flex flex-wrap gap-2" onsubmit="adminDecidePartnerContribution(event,'${x.id}')"><input name="ticket_until" type="date" class="auth-input max-w-48" aria-label="Fin de validité du ticket annuel"><button name="decision" value="approved" class="rounded-lg bg-emerald-600 text-white px-3 py-2 text-xs font-bold">Valider la cotisation</button><button name="decision" value="rejected" class="rounded-lg bg-rose-600 text-white px-3 py-2 text-xs font-bold">Refuser</button></form><p class="text-[10px] text-slate-500">La date de fin du ticket doit correspondre à la fin réelle de l’année scolaire, confirmée par la direction.</p></div>`);
    }
    el.innerHTML=parts.join('');
}

async function adminDecidePartnerContribution(e,id){
    e.preventDefault();const decision=e.submitter?.value||'approved';const raw=e.target.elements.ticket_until.value;
    if(decision==='approved'&&!raw)return showToast('Renseignez la date de validité du ticket après confirmation de l’année scolaire.','error');
    try{const {error}=await supabaseClient.rpc('admin_decide_partner_contribution',{p_contribution_id:id,p_decision:decision,p_ticket_valid_until:decision==='approved'?raw:null});if(error)throw error;showToast(decision==='approved'?'Cotisation validée. Le ticket est visible dans l’espace partenaire.':'Cotisation refusée.','success');await renderAdminLists();}
    catch(error){showToast(error.message||'Validation impossible.','error');}
}

function renderAdminFinanceRequests(rows){
    const el=document.getElementById('admin-finance-requests-list');if(!el)return;const pending=rows.filter(x=>x.status==='pending');
    el.innerHTML=pending.length?pending.map(x=>`<div class="rounded-xl border p-3 space-y-2"><p class="text-xs font-bold">${escapeHtml(x.request_type)} • ${Number(x.amount_ar).toLocaleString('fr-FR')} Ar • ${escapeHtml(x.user_id)}</p><p class="text-[10px] text-slate-500">${new Date(x.created_at).toLocaleString('fr-FR')}</p><form class="flex flex-wrap gap-2" onsubmit="adminReviewFinance(event,'${x.id}')"><input name="transfer_reference" class="auth-input flex-grow" placeholder="Référence du virement effectué (obligatoire pour approuver)"><button name="decision" value="approved" class="rounded-lg bg-emerald-600 text-white px-3 py-2 text-xs font-bold">Marquer payé</button><button name="decision" value="rejected" class="rounded-lg bg-rose-600 text-white px-3 py-2 text-xs font-bold">Refuser</button></form></div>`).join(''):'<p class="text-xs text-slate-500">Aucune demande financière en attente.</p>';
}

async function adminReviewFinance(e,id){e.preventDefault();const decision=e.submitter?.value||'approved';const ref=e.target.elements.transfer_reference.value.trim();if(decision==='approved'&&!ref)return showToast('Entrez la référence du virement réellement effectué.','error');try{const {error}=await supabaseClient.rpc('admin_review_finance_request',{p_request_id:id,p_decision:decision,p_transfer_reference:decision==='approved'?ref:null,p_review_note:null});if(error)throw error;showToast('Demande financière mise à jour.','success');await renderAdminLists();}catch(error){showToast(error.message||'Action impossible.','error');}}

function renderAdminStaffRequests(rows){
    const el=document.getElementById('admin-staff-requests-list');if(!el)return;const pending=rows.filter(x=>x.status==='pending');
    el.innerHTML=pending.length?pending.map(x=>`<div class="rounded-xl border p-3 space-y-2"><p class="text-xs font-bold">${escapeHtml(x.request_type)} • ${escapeHtml(x.teacher_id)}</p><p class="text-xs text-slate-600">${escapeHtml(x.reason)}</p><p class="text-[10px] text-slate-500">${x.start_date||''} → ${x.end_date||''} • ${escapeHtml(x.location||'')}</p><div class="flex gap-2"><button onclick="adminReviewStaff('${x.id}','approved')" class="rounded-lg bg-emerald-600 text-white px-3 py-2 text-xs font-bold">Accepter</button><button onclick="adminReviewStaff('${x.id}','rejected')" class="rounded-lg bg-rose-600 text-white px-3 py-2 text-xs font-bold">Refuser</button></div></div>`).join(''):'<p class="text-xs text-slate-500">Aucune demande du personnel en attente.</p>';
}
async function adminReviewStaff(id,decision){try{const {error}=await supabaseClient.rpc('admin_review_staff_request',{p_request_id:id,p_decision:decision,p_admin_note:null});if(error)throw error;showToast('Demande administrative traitée.','success');await renderAdminLists();}catch(error){showToast(error.message||'Action impossible.','error');}}

function renderAdminWorkdays(teachers){
    const el=document.getElementById('admin-teacher-workday-list');if(!el)return;
    el.innerHTML=teachers.length?teachers.map(t=>`<form class="rounded-xl border p-3 flex flex-wrap gap-2 items-center" onsubmit="adminRecordWorkday(event,'${t.id}')"><div class="min-w-40 flex-grow"><p class="text-xs font-bold">${escapeHtml(t.full_name||t.email)}</p><p class="text-[10px] text-slate-500">${escapeHtml(t.email)}</p></div><input name="work_date" type="date" required class="auth-input max-w-44"><input name="note" class="auth-input flex-grow" placeholder="Note (facultatif)"><button class="rounded-lg bg-navy-900 text-gold-400 px-3 py-2 text-xs font-bold">Valider journée × 6 000 Ar</button></form>`).join(''):'<p class="text-xs text-slate-500">Aucun enseignant approuvé.</p>';
}
async function adminRecordWorkday(e,teacherId){e.preventDefault();try{const {error}=await supabaseClient.rpc('admin_record_teacher_work_day',{p_teacher_id:teacherId,p_work_date:e.target.elements.work_date.value,p_note:e.target.elements.note.value||null});if(error)throw error;showToast('Journée validée et ajoutée au cumul salarial.','success');e.target.reset();await renderAdminLists();}catch(error){showToast(error.message||'Journée non enregistrée.','error');}}

async function renderAdminTeacherResources(rows){
    const el=document.getElementById('admin-teacher-resources-list');if(!el)return;
    if(!rows.length){el.innerHTML='<p class="text-xs text-slate-500">Aucune ressource déposée.</p>';return;}
    const items=[];for(const r of rows){const {data}=await supabaseClient.storage.from('teacher-course-files').createSignedUrl(r.file_path,900);items.push(`<div class="rounded-xl border p-3 flex flex-wrap items-center justify-between gap-2"><div><p class="text-xs font-bold">${escapeHtml(r.title)} • ${escapeHtml(r.subject_name)}</p><p class="text-[10px] text-slate-500">${escapeHtml(r.resource_type)} • ${(r.target_series||[]).map(escapeHtml).join(', ')} • ${r.published?'Publié':'Non publié'}</p>${data?.signedUrl?`<a class="text-xs underline text-indigo-700" target="_blank" rel="noopener noreferrer" href="${escapeHtml(data.signedUrl)}">Ouvrir le fichier</a>`:'<span class="text-xs text-rose-700">Fichier indisponible</span>'}</div><button onclick="adminPublishTeacherResource('${r.id}',${!r.published})" class="rounded-lg ${r.published?'bg-amber-100 text-amber-900':'bg-emerald-600 text-white'} px-3 py-2 text-xs font-bold">${r.published?'Dépublier':'Publier'}</button></div>`);}
    el.innerHTML=items.join('');
}
async function adminPublishTeacherResource(id,publish){try{const {error}=await supabaseClient.rpc('admin_publish_teacher_resource',{p_resource_id:id,p_publish:publish});if(error)throw error;showToast(publish?'Ressource publiée.':'Ressource retirée.','success');await renderAdminLists();}catch(error){showToast(error.message||'Action impossible.','error');}}

function prefillStudentReferralFromUrl(){
    const code=new URLSearchParams(location.search).get('ref');
    const field=document.getElementById('register-referral');
    if(field&&code&&/^[A-Za-z0-9]{8}$/.test(code))field.value=code.toUpperCase();
}

// Préremplir le code referral lorsqu'une nouvelle inscription arrive avec ?ref=XXXXXXXX.
prefillStudentReferralFromUrl();
