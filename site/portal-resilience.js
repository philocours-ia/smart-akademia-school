/* Smart Akademia School — résilience du portail promoteur.
 * Charge après role-portal.js via le service worker. Les panels indépendants
 * restent visibles même si une requête Supabase échoue.
 */
(() => {
  'use strict';

  const escape = value => typeof window.escapeHtml === 'function'
    ? window.escapeHtml(String(value ?? ''))
    : String(value ?? '').replace(/[&<>"']/g, char => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    })[char]);
  const money = value => Number(value || 0).toLocaleString('fr-FR');
  const displayDate = value => value ? new Date(value).toLocaleDateString('fr-FR') : '—';

  window.renderPromoterWorkspace = async function renderPromoterWorkspace(host, user) {
    if (!host || !user?.id || !window.supabaseClient) return;

    const load = async (label, query) => {
      try {
        const result = await query;
        if (result.error) return { label, data: [], error: result.error };
        return { label, data: result.data || [], error: null };
      } catch (error) {
        return { label, data: [], error };
      }
    };

    const [commissionResult, financeResult, referralResult] = await Promise.all([
      load('Commissions', supabaseClient.from('promoter_commissions')
        .select('id,student_id,amount_ar,created_at').eq('promoter_id', user.id)
        .order('created_at', { ascending: false })),
      load('Demandes financières', supabaseClient.from('finance_requests')
        .select('id,request_type,amount_ar,status,transfer_reference,created_at')
        .eq('user_id', user.id).order('created_at', { ascending: false })),
      load('Élèves parrainés', supabaseClient.rpc('list_akademia_promoter_referrals')),
    ]);

    const commissions = commissionResult.data;
    const finances = financeResult.data;
    const referrals = referralResult.data;
    const gross = commissions.reduce((total, row) => total + Number(row.amount_ar || 0), 0);
    const reserved = finances
      .filter(row => ['pending', 'approved'].includes(row.status))
      .reduce((total, row) => total + Number(row.amount_ar || 0), 0);
    const balance = Math.max(0, gross - reserved);
    const code = user.referralCode || '';
    const referralLink = code
      ? `${location.origin}${location.pathname}?ref=${encodeURIComponent(code)}`
      : '';

    const errors = [commissionResult, financeResult, referralResult]
      .filter(result => result.error)
      .map(result => `<li><strong>${escape(result.label)} :</strong> ${escape(result.error.message || 'lecture impossible')}</li>`)
      .join('');
    const errorPanel = errors
      ? `<section class="rounded-xl border border-amber-300 bg-amber-50 p-4 text-xs text-amber-950">
          <h3 class="font-bold">Certaines données sont temporairement indisponibles</h3>
          <ul class="mt-2 list-disc space-y-1 pl-5">${errors}</ul>
          <p class="mt-2">Les autres rubriques restent affichées. Vérifiez les migrations Supabase et les droits RLS, puis actualisez le portail.</p>
          <button type="button" onclick="refreshRolePortal()" class="mt-3 rounded-lg border border-amber-400 bg-white px-3 py-2 font-bold">Réessayer</button>
        </section>`
      : '';

    const financeMarkup = finances.length
      ? finances.map(row => `<article class="rounded-lg bg-slate-50 p-3 text-xs">
          <p class="font-bold text-navy-900">${money(row.amount_ar)} Ar · ${escape(row.request_type)}</p>
          <p class="mt-1 text-slate-600">Statut : ${escape(row.status)} · ${displayDate(row.created_at)}</p>
          ${row.transfer_reference ? `<p class="mt-1 text-slate-600">Référence de transfert : ${escape(row.transfer_reference)}</p>` : ''}
        </article>`).join('')
      : '<p class="text-xs text-slate-500">Aucune demande financière pour le moment.</p>';

    const referralMarkup = referrals.length
      ? referrals.map(row => `<article class="rounded-lg bg-slate-50 p-3 text-xs">
          <p class="font-bold text-navy-900">${escape(row.student_name || 'Élève')}</p>
          <p class="mt-1 text-slate-600">${escape(row.series || 'Classe non renseignée')} · Commission : ${money(row.commission_ar)} Ar</p>
          <p class="mt-1 text-slate-500">Validation : ${displayDate(row.approved_at)}</p>
        </article>`).join('')
      : '<p class="text-xs text-slate-500">Aucun élève validé par votre code de parrainage pour le moment.</p>';

    const linkMarkup = referralLink
      ? `<div class="flex flex-col gap-2 sm:flex-row">
          <input readonly id="promoter-referral-link" class="auth-input" value="${escape(referralLink)}" aria-label="Lien de parrainage">
          <button type="button" onclick="copyPromoterLink()" class="shrink-0 rounded-xl bg-navy-900 px-4 py-2 text-xs font-bold text-gold-400">Copier le lien</button>
        </div>`
      : '<p class="text-xs text-amber-800">Votre code de parrainage n’est pas encore disponible. Contactez l’administration si ce message persiste.</p>';

    host.innerHTML = `${errorPanel}
      <section class="rounded-2xl border border-indigo-200 bg-indigo-50 p-5">
        <p class="text-[10px] font-bold uppercase tracking-widest text-indigo-700">Espace promoteur</p>
        <h2 class="mt-1 font-display text-xl font-bold text-navy-950">Tableau de bord de parrainage</h2>
        <p class="mt-2 text-sm text-slate-700">Suivez vos élèves parrainés, vos commissions et vos demandes de paiement.</p>
      </section>
      <section class="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <article class="rounded-2xl border bg-white p-5"><p class="text-xs text-slate-500">Élèves validés</p><p class="mt-1 text-2xl font-bold text-navy-900">${referralResult.error ? '—' : referrals.length}</p></article>
        <article class="rounded-2xl border bg-white p-5"><p class="text-xs text-slate-500">Commissions cumulées</p><p class="mt-1 text-2xl font-bold text-navy-900">${commissionResult.error ? '—' : `${money(gross)} Ar`}</p></article>
        <article class="rounded-2xl border bg-white p-5"><p class="text-xs text-slate-500">Solde estimé disponible</p><p class="mt-1 text-2xl font-bold ${balance >= 30000 ? 'text-emerald-700' : 'text-amber-700'}">${commissionResult.error || financeResult.error ? '—' : `${money(balance)} Ar`}</p></article>
      </section>
      <section class="space-y-3 rounded-2xl border bg-white p-5">
        <h3 class="font-bold text-navy-900">Votre code et lien de parrainage</h3>
        ${code ? `<p class="font-mono text-2xl font-bold tracking-widest text-indigo-800">${escape(code)}</p>` : ''}
        ${linkMarkup}
        <p class="text-[11px] text-slate-500">La commission est comptabilisée après validation de l’inscription par l’administration.</p>
      </section>
      <section class="space-y-3 rounded-2xl border bg-white p-5">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div><h3 class="font-bold text-navy-900">Mes demandes financières</h3><p class="mt-1 text-xs text-slate-500">Le paiement peut être demandé à partir de 30 000 Ar disponibles.</p></div>
          <button type="button" onclick="requestPromoterPayout()" ${balance < 30000 || commissionResult.error || financeResult.error ? 'disabled' : ''}
            class="rounded-xl px-4 py-2 text-xs font-bold ${balance < 30000 || commissionResult.error || financeResult.error ? 'cursor-not-allowed bg-slate-100 text-slate-400' : 'bg-navy-900 text-gold-400'}">Demander mon paiement</button>
        </div>
        <div class="space-y-2">${financeResult.error ? '<p class="text-xs text-rose-700">Historique financier indisponible.</p>' : financeMarkup}</div>
      </section>
      <section class="space-y-3 rounded-2xl border bg-white p-5">
        <h3 class="font-bold text-navy-900">Élèves associés à mon code</h3>
        <div class="space-y-2">${referralResult.error ? '<p class="text-xs text-rose-700">Liste des filleuls indisponible.</p>' : referralMarkup}</div>
      </section>
      ${typeof window.professionalMessagingMarkup === 'function' ? window.professionalMessagingMarkup() : ''}`;

    if (typeof window.loadProfessionalMessages === 'function') {
      try { await window.loadProfessionalMessages(); }
      catch (error) { console.error('Chargement de la messagerie promoteur :', error); }
    }
  };
})();
