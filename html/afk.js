// ========================================
// whip_afk's page — over the camera while a player is away (client/showroom.lua), and the welcome back card
//
// Thin bars top and bottom, the make's logo, the model, the plate and how long they have been away, the car's
// numbers as bars against the best of its class, a vignette and grain, and a fade through black over each of the
// camera's cuts. The look is css/afk.css; this turns it on and off, fills
// it in, runs the clock (from how long they had been away when it started) and plays the dip. Our own page: whip's
// clean screen hides whip's page, not this one.
// ========================================

const el = document.getElementById('afk-show');
const logo = el.querySelector('.afk-logo');
const make = el.querySelector('.afk-make');
const model = el.querySelector('.afk-model');
const plate = el.querySelector('.afk-plate');
const clock = el.querySelector('.afk-time');
const dip = el.querySelector('.afk-dip');
const stats = el.querySelector('.afk-stats');
const statClass = el.querySelector('.afk-class');
const statRows = el.querySelector('.afk-rows');

let since = 0;
let timer = 0;

function tick() {
    const s = Math.floor(Math.max(0, Date.now() - since) / 1000);
    clock.textContent = Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
}

logo.addEventListener('error', () => { logo.hidden = true; });

/** The numbers: a row each, its bar filling to its share (css/afk.css grows them in, one after another). */
function fillStats(s) {
    statRows.textContent = '';
    const rows = s && Array.isArray(s.rows) ? s.rows : [];
    stats.hidden = rows.length === 0;
    statClass.textContent = (s && s.class) || '';
    rows.forEach((r, i) => {
        const row = document.createElement('div');
        row.className = 'afk-stat';
        const top = document.createElement('div');
        top.className = 'afk-stat-top';
        const label = document.createElement('span');
        label.textContent = String(r.label || '');
        const value = document.createElement('span');
        value.textContent = String(r.text || '');
        top.append(label, value);
        const bar = document.createElement('div');
        bar.className = 'afk-stat-bar';
        const fill = document.createElement('div');
        fill.className = 'afk-stat-fill';
        fill.style.setProperty('--share', String(Math.max(0, Math.min(1, Number(r.share) || 0))));
        fill.style.transitionDelay = (2.2 + i * 0.18) + 's';
        bar.appendChild(fill);
        row.append(top, bar);
        statRows.appendChild(row);
    });
}

const handlers = {};

handlers.afk = (d) => {
    const on = !!(d && d.on);
    clearInterval(timer);
    if (!on) { el.classList.remove('on'); return; }
    // Filled while off and laid out once before it goes on, so the bars grow in from nothing.
    el.classList.remove('on');
    // textContent only: a plate is a player's own words.
    make.textContent = d.make || '';
    model.textContent = d.model || '';
    plate.textContent = d.plate || '';
    plate.hidden = !d.plate;
    logo.hidden = !d.logo;
    if (d.logo) logo.src = 'nui://whip_core/html/img/manufacturers/' + encodeURIComponent(d.logo) + '.png';
    fillStats(d.stats);
    since = Date.now() - (Number(d.idleMs) || 0);
    tick();
    timer = setInterval(tick, 1000);
    void el.offsetWidth;
    el.classList.add('on');
};

// Welcome back: how long they were away, and the showroom's photo when there is one. Shown for a few seconds.
const back = document.getElementById('afk-back');
const backPhoto = back.querySelector('.afk-back-photo');
const backAway = back.querySelector('.afk-back-away');
let backTimer = 0;

function awayText(ms) {
    const s = Math.floor(Math.max(0, Number(ms) || 0) / 1000);
    const h = Math.floor(s / 3600);
    const m = Math.floor(s / 60) % 60;
    const clock = h > 0 ? h + ':' + String(m).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0')
        : m + ':' + String(s % 60).padStart(2, '0');
    return 'Away for ' + clock;
}

handlers.afkBack = (d) => {
    clearTimeout(backTimer);
    backAway.textContent = awayText(d && d.awayMs);
    const photo = d && typeof d.photo === 'string' && d.photo.startsWith('data:image/') ? d.photo : '';
    backPhoto.hidden = !photo;
    if (photo) backPhoto.src = photo;
    back.classList.remove('on');
    void back.offsetWidth;
    back.classList.add('on');
    backTimer = setTimeout(() => back.classList.remove('on'), photo ? 6500 : 4000);
};

// The dip: restarted each time, so two cuts close together still each get one.
handlers.afkDip = () => {
    dip.classList.remove('go');
    void dip.offsetWidth;
    dip.classList.add('go');
};

window.addEventListener('message', (e) => {
    const d = e.data;
    const fn = d && typeof d.action === 'string' ? handlers[d.action] : null;
    if (fn) fn(d);
});
