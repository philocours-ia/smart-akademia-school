/* Smart Akademia School — consentement d’adhésion enseignant.
 * Ce module est injecté dans la page par le service worker afin de préserver
 * le fichier HTML principal volumineux et généré manuellement.
 */
(() => {
  'use strict';

  const SCREEN_ID = 'applicant-signup-screen';
  const TYPE_ID = 'applicant-signup-type';
  const FORM_ID = 'teacher-adhesion-terms';
  const CONSENT_NAME = 'teacher-adhesion-consent';
  const NOTICE = 'Votre adhésion à la plateforme Smart Akademia School vous sanctionne d’une cotisation mensuelle de 5 000 Ar.';

  function notify(message) {
    if (typeof window.showToast === 'function') window.showToast(message, 'error');
    else window.alert(message);
  }

  function screenIsTeacherSignup() {
    const screen = document.getElementById(SCREEN_ID);
    const type = document.getElementById(TYPE_ID);
    return !!screen && !screen.classList.contains('hidden') && type?.value === 'teacher';
  }

  function buildTerms(form) {
    let terms = document.getElementById(FORM_ID);
    if (terms) return terms;

    terms = document.createElement('section');
    terms.id = FORM_ID;
    terms.className = 'rounded-xl border-2 border-amber-300 bg-amber-50 p-4 space-y-3';
    terms.setAttribute('aria-labelledby', `${FORM_ID}-title`);

    const title = document.createElement('h2');
    title.id = `${FORM_ID}-title`;
    title.className = 'text-sm font-bold text-navy-950';
    title.textContent = 'Conditions générales d’adhésion';

    const conditions = document.createElement('p');
    conditions.className = 'text-sm leading-relaxed text-amber-950';
    conditions.textContent = NOTICE;

    const prompt = document.createElement('p');
    prompt.className = 'text-xs font-semibold text-slate-700';
    prompt.textContent = 'Veuillez lire cette condition et choisir une réponse pour poursuivre.';

    const choices = document.createElement('fieldset');
    choices.className = 'flex flex-wrap gap-3 text-sm';
    const legend = document.createElement('legend');
    legend.className = 'sr-only';
    legend.textContent = 'Votre décision concernant les conditions d’adhésion';
    choices.append(legend);

    for (const [value, labelText] of [['accept', 'J’accepte'], ['refuse', 'Je refuse']]) {
      const label = document.createElement('label');
      label.className = 'inline-flex min-h-11 cursor-pointer items-center gap-2 rounded-lg border border-slate-300 bg-white px-4 py-2 font-semibold text-slate-800';
      const radio = document.createElement('input');
      radio.type = 'radio';
      radio.name = CONSENT_NAME;
      radio.value = value;
      radio.required = true;
      radio.className = 'accent-amber-700';
      label.append(radio, document.createTextNode(labelText));
      choices.append(label);
    }

    const refusal = document.createElement('p');
    refusal.className = 'hidden rounded-lg bg-rose-100 p-3 text-xs font-semibold text-rose-900';
    refusal.dataset.refusalNotice = 'true';
    refusal.textContent = 'Vous avez refusé les conditions. Vous ne pouvez pas poursuivre l’inscription comme enseignant.';

    terms.append(title, conditions, prompt, choices, refusal);
    const submit = form.querySelector('button[type="submit"]');
    if (submit) form.insertBefore(terms, submit);
    else form.append(terms);

    terms.addEventListener('change', (event) => {
      const choice = event.target;
      if (!(choice instanceof HTMLInputElement) || choice.name !== CONSENT_NAME) return;
      refusal.classList.toggle('hidden', choice.value !== 'refuse');
    });
    return terms;
  }

  function syncTerms() {
    const screen = document.getElementById(SCREEN_ID);
    const form = screen?.querySelector('form');
    if (!form) return;
    const terms = buildTerms(form);
    const enabled = screenIsTeacherSignup();
    terms.hidden = !enabled;
    terms.querySelectorAll(`input[name="${CONSENT_NAME}"]`).forEach((input) => {
      input.disabled = !enabled;
      input.required = enabled;
      if (!enabled) input.checked = false;
    });
    const refusal = terms.querySelector('[data-refusal-notice]');
    if (refusal && !enabled) refusal.classList.add('hidden');
  }

  function install() {
    const screen = document.getElementById(SCREEN_ID);
    if (!screen) return false;
    const form = screen.querySelector('form');
    if (!form) return false;

    syncTerms();
    screen.addEventListener('submit', (event) => {
      if (!screenIsTeacherSignup()) return;
      const selected = form.querySelector(`input[name="${CONSENT_NAME}"]:checked`);
      if (selected?.value === 'accept') return;

      event.preventDefault();
      event.stopImmediatePropagation();
      notify(selected?.value === 'refuse'
        ? 'Vous avez refusé les conditions générales d’adhésion ; l’inscription enseignant ne peut pas continuer.'
        : 'Pour poursuivre l’inscription enseignant, veuillez lire les conditions et choisir « J’accepte ».');
    }, true);

    // L’écran et les sections changent d’état lorsque le formulaire candidat s’ouvre.
    new MutationObserver(syncTerms).observe(screen, {
      attributes: true,
      attributeFilter: ['class'],
      childList: true,
      subtree: true,
    });
    document.addEventListener('click', () => queueMicrotask(syncTerms), true);
    document.addEventListener('change', syncTerms, true);
    return true;
  }

  if (!install()) {
    document.addEventListener('DOMContentLoaded', install, { once: true });
  }
})();
