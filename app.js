import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm';
import { SUPABASE_URL, SUPABASE_KEY } from './config.js';

const sb = createClient(SUPABASE_URL, SUPABASE_KEY);
const $ = (s) => document.querySelector(s);

// Cómo se muestra cada estado de la base de datos a cualquier persona
const ESTADOS = {
  'Vencida':    { label: 'Atrasada',        cls: 'rojo',  orden: 0, ayuda: 'Ya pasó la fecha' },
  'Por vencer': { label: 'Vence pronto',    cls: 'ambar', orden: 1, ayuda: 'Dentro del periodo de aviso' },
  'En tiempo':  { label: 'Al día',          cls: 'verde', orden: 2, ayuda: 'La fecha aún está lejos' },
  'Permanente': { label: 'Vigilar siempre', cls: 'azul',  orden: 3, ayuda: 'Aplica todo el tiempo' },
  'Cumplida':   { label: 'Cumplida',        cls: 'gris',  orden: 4, ayuda: 'Ya quedó atendida' },
};
const CATEGORIAS = {
  'Pagar': '💵', 'Reportar': '📄', 'Mantener': '🛡️', 'Hacer': '✅', 'No hacer': '⛔', 'Notificar': '📣',
};
const QUE_SIGNIFICA = {
  'Pagar': 'Hay que pagar', 'Reportar': 'Hay que entregar información', 'Mantener': 'Hay que mantener algo vigente',
  'Hacer': 'Hay que hacer algo', 'No hacer': 'Está prohibido hacer algo', 'Notificar': 'Hay que avisar',
};

const state = {
  obligaciones: [], alertas: [], cumplimientos: [], contratos: [], correos: [], areas: [], respuestas: [],
  estado: null, contrato: 'Todos', q: '',
};
const ICONO_CONTRATO = { 'Crédito': '📄', 'Fideicomiso': '🏦' };
const ESTADO_CORREO = {
  pendiente: { label: 'Pendiente de envío', cls: 'ambar' },
  enviado: { label: 'Enviado', cls: 'verde' },
  error: { label: 'Error al enviar', cls: 'rojo' },
  cancelado: { label: 'Cancelado', cls: 'gris' },
};
const dinero = (n, m) => n == null ? '—' : '$' + new Intl.NumberFormat('es-MX', { maximumFractionDigits: 0 }).format(n) + ' ' + (m || 'MXN');
const ETIQUETA_CONTEO = { 'Vencida': ['atrasada', 'atrasadas'], 'Por vencer': ['vence pronto', 'vencen pronto'], 'En tiempo': ['al día', 'al día'] };

// ---------- utilidades ----------
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fecha = (iso) => {
  if (!iso) return '—';
  const [y, m, d] = iso.slice(0, 10).split('-');
  return `${d}/${m}/${y}`;
};
const fechaLarga = (iso) => new Date(iso + 'T12:00:00').toLocaleDateString('es-MX', { weekday: 'short', day: 'numeric', month: 'short' });
const cuando = (d) => {
  if (d === null || d === undefined) return '';
  if (d < 0) return `Atrasada ${-d} ${-d === 1 ? 'día' : 'días'}`;
  if (d === 0) return 'Vence hoy';
  if (d === 1) return 'Vence mañana';
  return `Faltan ${d} días`;
};
const plural = (n, uno, varios) => `${n} ${n === 1 ? uno : varios}`;
const store = {
  get(k, def) { try { return JSON.parse(localStorage.getItem(k)) ?? def; } catch { return def; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* sin almacenamiento */ } },
};
function toast(msg) {
  const t = $('#toast');
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toast.t);
  toast.t = setTimeout(() => t.classList.remove('show'), 3800);
}

// ---------- datos ----------
async function cargar() {
  const [ob, al, cu, co, ma, ar, re] = await Promise.all([
    sb.from('v_obligaciones').select('*'),
    sb.from('alertas').select('*, obligaciones(titulo)')
      .order('leida', { ascending: true }).order('fecha_objetivo', { ascending: true }).limit(60),
    sb.from('cumplimientos').select('*').order('fecha_cumplimiento', { ascending: false }),
    sb.from('contratos').select('*').order('tipo'),
    sb.from('correos').select('*, obligaciones(titulo)').order('created_at', { ascending: false }).limit(200),
    sb.from('areas').select('*').order('es_direccion_general').order('nombre'),
    sb.from('respuestas').select('*').order('recibido_at', { ascending: false }),
  ]);
  const err = ob.error || al.error || cu.error || co.error || ma.error || ar.error || re.error;
  if (err) {
    $('#heroTitulo').textContent = 'No se pudo conectar con la base de datos';
    $('#heroSub').textContent = err.message;
    return false;
  }
  state.obligaciones = ob.data;
  state.alertas = al.data;
  state.cumplimientos = cu.data;
  state.contratos = co.data;
  state.correos = ma.data;
  state.areas = ar.data;
  state.respuestas = re.data;
  return true;
}

function filtradas() {
  const q = state.q.trim().toLowerCase();
  return state.obligaciones
    .filter((o) => state.contrato === 'Todos' || o.contrato_tipo === state.contrato)
    .filter((o) => !state.estado || o.estado === state.estado)
    .filter((o) => !q || [o.titulo, o.explicacion_simple, o.responsable, o.categoria, o.clausula, o.contrato_nombre].join(' ').toLowerCase().includes(q))
    .sort((a, b) => ESTADOS[a.estado].orden - ESTADOS[b.estado].orden
      || (a.dias_restantes ?? 9999) - (b.dias_restantes ?? 9999)
      || a.titulo.localeCompare(b.titulo, 'es'));
}

// ---------- render ----------
function renderHero() {
  const obs = state.obligaciones.filter((o) => state.contrato === 'Todos' || o.contrato_tipo === state.contrato);
  const n = (e) => obs.filter((o) => o.estado === e).length;
  const venc = n('Vencida'), pronto = n('Por vencer');
  $('#contratoLinea').textContent = 'Proyecto ficticio · Crédito y fideicomiso';
  const partes = new Map();
  state.contratos.forEach((c) => c.partes.forEach((p) => {
    const rol = p.rol.split(' y ')[0];
    if (!partes.has(p.nombre)) partes.set(p.nombre, rol);
  }));
  $('#partesHero').innerHTML = [...partes].map(([n, r]) => `<span><b>${esc(r)}:</b> ${esc(n)}</span>`).join('');

  let titulo, sub;
  if (venc) {
    titulo = `Hay ${plural(venc, 'obligación atrasada', 'obligaciones atrasadas')}${pronto ? ` y ${plural(pronto, 'que vence', 'que vencen')} pronto` : ''}.`;
    sub = 'Empieza por las rojas: son las que ya pasaron su fecha. Abre cada una para ver qué hay que hacer y qué pasa si no se atiende.';
  } else if (pronto) {
    titulo = `Todo al corriente, pero ${plural(pronto, 'obligación vence', 'obligaciones vencen')} pronto.`;
    sub = 'Revisa las amarillas para tenerlas listas antes de su fecha.';
  } else {
    titulo = '¡Todo al corriente! 🎉';
    sub = 'No hay obligaciones atrasadas ni por vencer en este momento.';
  }
  $('#heroTitulo').textContent = titulo;
  $('#heroSub').textContent = sub;

  const pct = obs.length ? Math.round(((obs.length - venc) / obs.length) * 100) : 100;
  $('#ringPct').textContent = pct + '%';
  const fg = $('#ringFg');
  fg.style.strokeDashoffset = String(326.7 * (1 - pct / 100));
  fg.style.stroke = pct === 100 ? 'var(--verde)' : pct >= 85 ? 'var(--ambar)' : 'var(--rojo)';
  $('#ring').setAttribute('aria-label', `${pct}% de las obligaciones están al corriente`);
}

function renderContratos() {
  $('#contratos').innerHTML = state.contratos.map((c) => {
    const obs = state.obligaciones.filter((o) => o.contrato_id === c.id);
    const cuenta = (e) => obs.filter((o) => o.estado === e).length;
    const pills = ['Vencida', 'Por vencer', 'En tiempo'].filter((e) => cuenta(e))
      .map((e) => `<span class="pill ${ESTADOS[e].cls}"><span class="dot"></span>${plural(cuenta(e), ...ETIQUETA_CONTEO[e])}</span>`).join('');
    return `<button class="contrato-btn" data-ver-contrato="${c.id}">
      <span class="contrato-ico" aria-hidden="true">${ICONO_CONTRATO[c.tipo]}</span>
      <span><h3>${c.tipo === 'Crédito' ? 'Contrato de crédito' : 'Fideicomiso'}</h3>
        <p>${esc(c.contraparte)}${c.monto ? ' · ' + dinero(c.monto, c.moneda) : ''} · ${plural(obs.length, 'obligación', 'obligaciones')}</p>
        <span class="mini">${pills}</span></span>
      <span class="go">Ver detalle →</span></button>`;
  }).join('');
}

function abrirContrato(id) {
  const c = state.contratos.find((x) => x.id === id);
  if (!c) return;
  const obs = state.obligaciones.filter((o) => o.contrato_id === id)
    .sort((a, b) => ESTADOS[a.estado].orden - ESTADOS[b.estado].orden || (a.dias_restantes ?? 9999) - (b.dias_restantes ?? 9999));
  $('#detContenido').innerHTML = `
    <span class="pill azul">${ICONO_CONTRATO[c.tipo]} ${c.tipo === 'Crédito' ? 'Contrato de crédito' : 'Fideicomiso'} · ${esc(c.proyecto || '')}</span>
    <h2 id="detTitulo">${esc(c.nombre)}</h2>
    <p class="lead">${esc(c.resumen || '')}</p>
    <div class="info"><b>¿Para qué sirve?</b> ${esc(c.objeto || '—')}</div>
    <b>Partes</b>
    <div class="det-grid">${c.partes.map((p) => `<div class="det-box"><small>${esc(p.rol)}</small>${esc(p.nombre)}</div>`).join('')}</div>
    <div class="det-grid">
      ${c.monto ? `<div class="det-box"><small>Monto</small>${dinero(c.monto, c.moneda)}</div>` : ''}
      <div class="det-box"><small>Plazo</small>${esc(c.plazo || '—')}</div>
      <div class="det-box"><small>Firma</small>${fecha(c.fecha_firma)}</div>
      <div class="det-box"><small>Vencimiento</small>${c.fecha_vencimiento ? fecha(c.fecha_vencimiento) : 'Mientras exista el crédito'}</div>
    </div>
    <div class="det-box" style="margin-bottom:10px"><small>Garantías / patrimonio</small>${esc(c.garantias || '—')}</div>
    <div class="det-box"><small>Ley y tribunales</small>${esc(c.ley_jurisdiccion || '—')}</div>
    <h3 style="margin:18px 0 8px">Obligaciones de este contrato (${obs.length})</h3>
    <div class="alert-list">${obs.map((o) => `<button class="al ${ESTADOS[o.estado].cls}" data-abrir-ob="${o.id}">
      <b>${CATEGORIAS[o.categoria]} ${esc(o.titulo)}</b>
      <small>${ESTADOS[o.estado].label}${o.proxima_fecha ? ' · ' + cuando(o.dias_restantes) + ' (' + fecha(o.proxima_fecha) + ')' : ''} · ${esc(o.area_nombre || o.responsable || '')}</small></button>`).join('')}</div>`;
  const dlg = $('#detalle');
  if (!dlg.open) dlg.showModal();
  dlg.scrollTop = 0;
}

function renderCorreos() {
  const n = (e) => state.correos.filter((c) => c.estado === e).length;
  $('#mailStats').innerHTML = `<div><b>${n('pendiente')}</b><small>Por enviar</small></div>
    <div><b>${n('enviado')}</b><small>Enviados</small></div>
    <div><b>${state.correos.filter((c) => c.tipo === 'incumplimiento' && c.estado !== 'cancelado').length}</b><small>A Dirección General</small></div>
    <div><b>${state.respuestas.length}</b><small>Respuestas recibidas</small></div>
    <div><b>${state.respuestas.filter((r) => !r.revisada).length}</b><small>Sin revisar</small></div>
    ${(() => {
      // La carpeta del proyecto se deduce de las respuestas guardadas (no se escribe en el código)
      const url = state.respuestas.find((r) => r.carpeta_url)?.carpeta_url;
      const raiz = url ? url.slice(0, url.indexOf('/Respuestas%20de%20') ) : null;
      return `<div><b>📁</b><small>${raiz ? `<a href="${esc(raiz)}" target="_blank" rel="noopener">Carpeta OneDrive</a>` : 'Carpeta OneDrive'}</small></div>`;
    })()}`;
  $('#areasLista').innerHTML = state.areas.map((a) => `<li><b>${a.es_direccion_general ? '⭐ ' : ''}${esc(a.nombre)}</b>
    <span>${esc(a.titular || '')}<br>${esc(a.correo)}</span></li>`).join('');
}

const mailto = (c) => `mailto:${encodeURIComponent(c.para)}?${c.cc ? 'cc=' + encodeURIComponent(c.cc) + '&' : ''}subject=${encodeURIComponent(c.asunto)}&body=${encodeURIComponent(c.cuerpo)}`;

function abrirBandeja(aviso = '') {
  const orden = { pendiente: 0, error: 1, enviado: 2, cancelado: 3 };
  const lista = [...state.correos].sort((a, b) => orden[a.estado] - orden[b.estado]
    || (a.tipo === 'incumplimiento' ? -1 : 1) - (b.tipo === 'incumplimiento' ? -1 : 1)
    || a.fecha_objetivo.localeCompare(b.fecha_objetivo));
  $('#detContenido').innerHTML = `
    <span class="pill azul">✉️ Bandeja de correos</span>
    <h2 id="detTitulo">Recordatorios y avisos de incumplimiento</h2>
    ${aviso ? `<div class="info">${aviso}</div>` : ''}
    <div class="alert-list" style="margin-top:12px">${lista.length ? lista.map((c) => {
      const e = ESTADO_CORREO[c.estado];
      const tipo = c.tipo === 'incumplimiento' ? '🚨 Aviso de incumplimiento' : '⏰ Recordatorio';
      return `<div class="correo ${c.tipo === 'incumplimiento' ? 'rojo' : e.cls}">
        <div><span class="pill ${e.cls}"><span class="dot"></span>${e.label}</span> <small class="muted">${tipo}</small></div>
        <b>${esc(c.asunto)}</b>
        <div class="para">Para: ${esc(c.para)}${c.cc ? ' · CC: ' + esc(c.cc) : ''}${c.enviado_at ? ' · enviado ' + fecha(c.enviado_at) : ''}</div>
        ${c.error && c.estado !== 'enviado' ? `<div class="para">${esc(c.error)}</div>` : ''}
        <pre>${esc(c.cuerpo)}</pre>
        <div class="correo-acc">
          <button class="btn ghost" data-toggle-correo>Ver mensaje</button>
          ${c.estado === 'pendiente' || c.estado === 'error' ? `<a class="btn ghost" href="${mailto(c)}">Abrir en mi correo</a>` : ''}
        </div></div>`;
    }).join('') : '<p class="empty">No hay correos todavía.</p>'}</div>`;
  const dlg = $('#detalle');
  if (!dlg.open) dlg.showModal();
}

async function enviarCorreos() {
  const btn = $('#btnEnviarCorreos');
  btn.disabled = true;
  btn.textContent = 'Revisando fechas…';
  const { data, error } = await sb.functions.invoke('enviar-correos', { body: {} });
  btn.disabled = false;
  btn.textContent = 'Enviar recordatorios por correo';
  if (error) { toast('No se pudo ejecutar el envío: ' + error.message); return; }
  await cargar();
  render();
  if (data.configurado && !data.errores) {
    toast(`Listo: ${plural(data.enviados, 'correo enviado', 'correos enviados')} desde Gmail.`);
  } else if (data.configurado) {
    abrirBandeja(`<b>Gmail rechazó ${plural(data.errores, 'envío', 'envíos')}.</b> ${esc(data.ultimoError || '')}<br>Revisa que la contraseña de aplicación de Gmail esté bien capturada en Supabase. Los correos con error se reintentan en el siguiente envío.`);
  } else {
    abrirBandeja(`<b>El envío por Gmail aún no está conectado.</b> Los ${plural(data.pendientes, 'correo quedó listo', 'correos quedaron listos')} en esta bandeja: puedes enviarlos uno por uno con <b>"Abrir en mi correo"</b>. Para que salgan solos desde Gmail, falta capturar la cuenta y la contraseña de aplicación en Supabase (ver README).`);
  }
}

function renderCards() {
  const obs = state.obligaciones.filter((o) => state.contrato === 'Todos' || o.contrato_tipo === state.contrato);
  $('#cards').innerHTML = Object.entries(ESTADOS).map(([k, e]) => {
    const n = obs.filter((o) => o.estado === k).length;
    return `<button class="card ${e.cls}" data-estado="${k}" aria-pressed="${state.estado === k}">
      <b>${n}</b><span>${e.label}</span><small>${e.ayuda}</small></button>`;
  }).join('');
}

function renderTimeline() {
  const prox = state.obligaciones
    .filter((o) => state.contrato === 'Todos' || o.contrato_tipo === state.contrato)
    .filter((o) => o.proxima_fecha && o.dias_restantes <= 60)
    .sort((a, b) => a.dias_restantes - b.dias_restantes);
  $('#timeline').innerHTML = prox.length ? prox.map((o) => {
    const e = ESTADOS[o.estado];
    return `<button class="tl-item ${e.cls}" data-id="${o.id}">
      <div class="tl-date">${fechaLarga(o.proxima_fecha)}</div>
      <div class="tl-when">${cuando(o.dias_restantes)}</div>
      <div class="tl-title">${CATEGORIAS[o.categoria]} ${esc(o.titulo)}</div></button>`;
  }).join('') : '<p class="empty">No hay fechas en los próximos 60 días.</p>';
}

function renderFiltros() {
  $('#segContrato').innerHTML = ['Todos', 'Crédito', 'Fideicomiso'].map((c) =>
    `<button role="tab" data-contrato="${c}" aria-selected="${state.contrato === c}">${c}</button>`).join('');
  $('#chipsEstado').innerHTML = `<button class="chip" data-estado="" aria-pressed="${!state.estado}">Todas</button>` +
    Object.entries(ESTADOS).map(([k, e]) =>
      `<button class="chip ${e.cls}" data-estado="${k}" aria-pressed="${state.estado === k}"><span class="dot"></span>${e.label}</button>`).join('');
}

function renderLista() {
  const obs = filtradas();
  $('#listaCuenta').textContent = `${plural(obs.length, 'obligación', 'obligaciones')} · ordenadas de la más urgente a la menos urgente`;
  $('#lista').innerHTML = obs.length ? obs.map((o) => {
    const e = ESTADOS[o.estado];
    const fechaTxt = o.proxima_fecha
      ? `<div class="when">${cuando(o.dias_restantes)}<small>${fecha(o.proxima_fecha)}</small></div>`
      : `<div class="when">${o.periodicidad === 'Por evento' ? 'Solo si ocurre algo' : o.estado === 'Cumplida' ? 'Ya cumplida' : 'Todo el tiempo'}<small>${o.ultima_fecha_cumplimiento ? 'Última: ' + fecha(o.ultima_fecha_cumplimiento) : '&nbsp;'}</small></div>`;
    const puedeCumplir = o.proxima_fecha !== null;
    return `<article class="ob ${e.cls}">
      <div class="ob-icon" aria-hidden="true">${CATEGORIAS[o.categoria]}</div>
      <div>
        <h3>${esc(o.titulo)}</h3>
        <p>${esc(o.explicacion_simple)}</p>
        <div class="meta">
          <span class="tag">${o.contrato_tipo}</span>
          <span class="tag">${esc(o.periodicidad)}</span>
          <span class="tag">👤 ${esc(o.responsable || 'Sin responsable')}</span>
          ${o.prioridad === 'Alta' ? '<span class="tag">⚠️ Prioridad alta</span>' : ''}
          ${(() => {
            const rs = state.respuestas.filter((r) => r.obligacion_id === o.id);
            const sinRevisar = rs.filter((r) => !r.revisada).length;
            return rs.length ? `<span class="tag ${sinRevisar ? 'tag-nueva' : ''}">📨 ${plural(rs.length, 'respuesta', 'respuestas')}${sinRevisar ? ` · ${sinRevisar} sin revisar` : ''}</span>` : '';
          })()}
        </div>
      </div>
      <div class="ob-side">
        <span class="pill"><span class="dot"></span>${e.label}</span>
        ${fechaTxt}
        <div class="ob-actions">
          <button class="btn ghost" data-ver="${o.id}">Ver detalle</button>
          ${puedeCumplir ? `<button class="btn ok" data-cumplir="${o.id}">Ya se cumplió</button>` : ''}
        </div>
      </div>
    </article>`;
  }).join('') : '<p class="empty">No hay obligaciones con estos filtros.</p>';
}

function renderAlertas() {
  const noLeidas = state.alertas.filter((a) => !a.leida).length;
  const bc = $('#bellCount');
  bc.hidden = !noLeidas;
  bc.textContent = noLeidas;
  $('#alertasLista').innerHTML = state.alertas.length ? state.alertas.map((a) => {
    const cls = a.tipo === 'vencida' ? 'rojo' : 'ambar';
    return `<button class="al ${cls} ${a.leida ? 'leida' : ''}" data-id="${a.obligacion_id}">
      <b>${esc(a.mensaje)}</b>
      <small>${a.tipo === 'vencida' ? 'Atrasada' : 'Aviso previo'} · generado el ${fecha(a.created_at)}</small></button>`;
  }).join('') : '<p class="empty">No hay avisos. 🎉</p>';
}

function render() {
  renderHero(); renderContratos(); renderCards(); renderTimeline(); renderFiltros(); renderLista(); renderAlertas(); renderCorreos();
}

// ---------- detalle y registro de cumplimiento ----------
function abrirDetalle(id, enfocarFormulario = false) {
  const o = state.obligaciones.find((x) => x.id === id);
  if (!o) return;
  const e = ESTADOS[o.estado];
  const hist = state.cumplimientos.filter((c) => c.obligacion_id === id);
  const puedeCumplir = o.proxima_fecha !== null;
  $('#detContenido').innerHTML = `
    <span class="pill ${e.cls}"><span class="dot"></span>${e.label}${o.proxima_fecha ? ' · ' + cuando(o.dias_restantes) : ''}</span>
    <h2 id="detTitulo">${CATEGORIAS[o.categoria]} ${esc(o.titulo)}</h2>
    <p class="lead">${esc(o.explicacion_simple)}</p>
    <div class="risk"><b>¿Qué pasa si no se cumple?</b><br>${esc(o.consecuencia || 'No especificado en el contrato.')}</div>
    <div class="det-grid">
      <div class="det-box"><small>Tipo</small>${QUE_SIGNIFICA[o.categoria]}</div>
      <div class="det-box"><small>Próxima fecha</small>${o.proxima_fecha ? fecha(o.proxima_fecha) : (o.periodicidad === 'Por evento' ? 'Cuando ocurra el evento' : 'No aplica')}</div>
      <div class="det-box"><small>¿Cada cuánto?</small>${esc(o.periodicidad)}</div>
      <div class="det-box"><small>Área responsable</small>${esc(o.area_nombre || o.responsable || '—')}${o.area_titular ? `<br><span class="muted">${esc(o.area_titular)} · ${esc(o.area_correo)}</span>` : ''}</div>
      <div class="det-box"><small>Contrato</small>${esc(o.contrato_nombre)}<br><span class="muted">${esc(o.contraparte)}</span></div>
      <div class="det-box"><small>Dónde lo dice</small>${esc(o.clausula || '—')}</div>
    </div>
    <div><b>Avisos en la app:</b> <span class="muted">${[...o.dias_aviso].sort((a, b) => b - a).map((d) => d + (d === 1 ? ' día' : ' días')).join(', ')} antes de la fecha.</span></div>
    ${o.proxima_fecha ? `<div style="margin-top:6px"><b>Correos:</b> <span class="muted">recordatorio al área 45 días antes${o.estado === 'Vencida' ? '; como ya venció, se avisa a Dirección General' : '; si vence sin atenderse, aviso a Dirección General'}.</span>
      ${state.correos.filter((c) => c.obligacion_id === o.id).map((c) => `<br><span class="pill ${ESTADO_CORREO[c.estado].cls}" style="margin-top:6px"><span class="dot"></span>${c.tipo === 'incumplimiento' ? 'Incumplimiento → Dirección General' : 'Recordatorio → ' + esc(o.area_nombre || '')}: ${ESTADO_CORREO[c.estado].label.toLowerCase()}</span>`).join('')}</div>` : ''}
    ${(() => {
      const rs = state.respuestas.filter((r) => r.obligacion_id === id);
      if (!rs.length) return '';
      return `<div style="margin-top:14px"><b>📨 Respuestas de las áreas (${rs.length})</b>
        <div class="alert-list" style="margin-top:8px">${rs.map((r) => `<div class="correo ${r.revisada ? 'gris' : 'azul'}">
          <div><span class="pill ${r.revisada ? 'gris' : 'azul'}"><span class="dot"></span>${r.revisada ? 'Revisada' : 'Nueva'}</span>
            <small class="muted"> ${esc(r.remitente)} · ${fecha(r.recibido_at)}</small></div>
          <div style="white-space:pre-wrap;font-size:14px">${esc(r.texto || '(sin texto)')}</div>
          ${r.archivos.length ? `<div class="para">📎 ${r.archivos.map((a) => `<a href="${esc(a.url)}" target="_blank" rel="noopener">${esc(a.nombre)}</a>`).join(' · ')}</div>` : ''}
          <div class="correo-acc">
            ${r.carpeta_url ? `<a class="btn ghost" href="${esc(r.carpeta_url)}" target="_blank" rel="noopener">📁 Abrir carpeta en OneDrive</a>` : ''}
            ${puedeCumplir ? `<button class="btn ghost" data-usar-respuesta="${r.id}">Usar como evidencia</button>` : ''}
            ${r.revisada ? '' : `<button class="btn ghost" data-revisar-respuesta="${r.id}">Marcar revisada</button>`}
          </div></div>`).join('')}</div></div>`;
    })()}
    <div style="margin-top:12px"><b>Historial de cumplimiento</b>
      ${hist.length ? `<ul class="hist">${hist.map((c) => `<li><b>${fecha(c.fecha_cumplimiento)}</b>${c.periodo_fecha ? ` · periodo del ${fecha(c.periodo_fecha)}` : ''}${c.registrado_por ? ' · ' + esc(c.registrado_por) : ''}<br><span class="muted">${esc(c.nota || '')}</span>${c.evidencia_url ? ` · <a href="${esc(c.evidencia_url)}" target="_blank" rel="noopener">evidencia</a>` : ''}</li>`).join('')}</ul>` : '<p class="muted" style="margin:4px 0">Aún no hay registros.</p>'}
    </div>
    ${puedeCumplir ? `
    <form class="form" id="formCumplir">
      <h3>✅ Registrar que ya se cumplió</h3>
      <label>¿Qué se hizo? <textarea name="nota" placeholder="Ej.: Se enviaron los estados financieros al banco por correo." required></textarea></label>
      <label>Liga a la evidencia (opcional) <input name="evidencia" type="url" placeholder="https://… (SharePoint, correo, acuse)"></label>
      <label>¿Quién lo registra? <input name="quien" placeholder="Tu nombre"></label>
      <button class="btn ok" type="submit">Guardar cumplimiento</button>
      ${o.periodicidad !== 'Única' ? `<small class="muted">Al guardar, la próxima fecha se recorre automáticamente (${o.periodicidad.toLowerCase()}).</small>` : ''}
    </form>` : `<p class="muted" style="margin-top:14px">Esta obligación no tiene fecha: se vigila de forma permanente o solo cuando ocurre un evento.</p>`}
  `;
  const dlg = $('#detalle');
  if (!dlg.open) dlg.showModal();
  const form = $('#formCumplir');
  if (form) {
    form.addEventListener('submit', (ev) => guardarCumplimiento(ev, o));
    if (enfocarFormulario) form.querySelector('textarea').focus();
  }
}

async function guardarCumplimiento(ev, o) {
  ev.preventDefault();
  const f = new FormData(ev.target);
  const btn = ev.target.querySelector('button[type=submit]');
  btn.disabled = true;
  btn.textContent = 'Guardando…';
  const quien = String(f.get('quien') || '').trim();
  if (quien) store.set('lawgic.nombre', quien);
  const { data, error } = await sb.rpc('registrar_cumplimiento', {
    p_obligacion: o.id, p_nota: f.get('nota'), p_evidencia: f.get('evidencia'), p_registrado_por: quien,
  });
  if (error) {
    btn.disabled = false;
    btn.textContent = 'Guardar cumplimiento';
    toast('No se pudo guardar: ' + error.message);
    return;
  }
  $('#detalle').close();
  await cargar();
  render();
  toast(data.proxima_fecha ? `¡Listo! Próxima fecha: ${fecha(data.proxima_fecha)}.` : '¡Listo! Quedó registrada como cumplida.');
}

// ---------- avisos ----------
function abrirDrawer(abrir) {
  $('#drawer').setAttribute('aria-hidden', String(!abrir));
}

function notificarNavegador() {
  if (!('Notification' in window) || Notification.permission !== 'granted') return;
  const vistas = store.get('lawgic.notificadas', []);
  const nuevas = state.alertas.filter((a) => !a.leida && !vistas.includes(a.id));
  if (!nuevas.length) return;
  const venc = nuevas.filter((a) => a.tipo === 'vencida').length;
  new Notification(`Valle Aurora: ${plural(nuevas.length, 'aviso nuevo', 'avisos nuevos')}`, {
    body: (venc ? `${plural(venc, 'atrasada', 'atrasadas')}. ` : '') + nuevas.slice(0, 3).map((a) => a.mensaje).join('\n'),
    tag: 'valle-aurora-avisos',
  });
  store.set('lawgic.notificadas', [...vistas, ...nuevas.map((a) => a.id)].slice(-300));
}

function actualizarBotonNotif() {
  const b = $('#btnNotif');
  if (!('Notification' in window)) { b.hidden = true; return; }
  if (Notification.permission === 'granted') { b.textContent = '🔔 Avisos activados'; b.disabled = true; }
  if (Notification.permission === 'denied') { b.textContent = 'Avisos bloqueados en este navegador'; b.disabled = true; }
}

// ---------- calendario (.ics con recordatorios) ----------
function descargarCalendario() {
  const pad = (n) => String(n).padStart(2, '0');
  const ahora = new Date();
  const stamp = `${ahora.getUTCFullYear()}${pad(ahora.getUTCMonth() + 1)}${pad(ahora.getUTCDate())}T${pad(ahora.getUTCHours())}${pad(ahora.getUTCMinutes())}00Z`;
  const icsText = (s) => String(s).replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n');
  const eventos = state.obligaciones.filter((o) => o.proxima_fecha).map((o) => {
    const d = o.proxima_fecha.replace(/-/g, '');
    const fin = new Date(o.proxima_fecha + 'T12:00:00'); fin.setDate(fin.getDate() + 1);
    const dFin = `${fin.getFullYear()}${pad(fin.getMonth() + 1)}${pad(fin.getDate())}`;
    const alarmas = [...new Set(o.dias_aviso)].map((n) =>
      `BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:${icsText(o.titulo)}\r\nTRIGGER:-P${n}D\r\nEND:VALARM`).join('\r\n');
    return [
      'BEGIN:VEVENT', `UID:${o.id}-${d}@valle-aurora`, `DTSTAMP:${stamp}`, `DTSTART;VALUE=DATE:${d}`, `DTEND;VALUE=DATE:${dFin}`,
      `SUMMARY:${icsText('⚖️ ' + o.titulo)}`,
      `DESCRIPTION:${icsText(`${o.explicacion_simple}\n\nSi no se cumple: ${o.consecuencia || '—'}\n${o.contrato_nombre} · ${o.clausula || ''}\nResponsable: ${o.responsable || '—'}`)}`,
      alarmas, 'END:VEVENT',
    ].join('\r\n');
  });
  const ics = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Parque Solar Valle Aurora//Semaforo de cumplimiento//ES', 'CALSCALE:GREGORIAN', ...eventos, 'END:VCALENDAR'].join('\r\n');
  const url = URL.createObjectURL(new Blob([ics], { type: 'text/calendar;charset=utf-8' }));
  const a = Object.assign(document.createElement('a'), { href: url, download: 'obligaciones-valle-aurora.ics' });
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
  toast(`Se descargaron ${plural(eventos.length, 'fecha', 'fechas')}. Ábrelo para agregarlas a Outlook o Google Calendar.`);
}

// ---------- eventos ----------
document.addEventListener('click', async (ev) => {
  const t = ev.target.closest('button, .al');
  if (!t) return;
  if (t.dataset.estado !== undefined && (t.classList.contains('card') || t.classList.contains('chip'))) {
    state.estado = t.dataset.estado && state.estado !== t.dataset.estado ? t.dataset.estado : null;
    render();
    if (t.classList.contains('card')) $('#lista').scrollIntoView({ behavior: 'smooth', block: 'start' });
  } else if (t.dataset.contrato) {
    state.contrato = t.dataset.contrato; render();
  } else if (t.dataset.ver) {
    abrirDetalle(t.dataset.ver);
  } else if (t.dataset.cumplir) {
    abrirDetalle(t.dataset.cumplir, true);
  } else if (t.dataset.verContrato) {
    abrirContrato(t.dataset.verContrato);
  } else if (t.dataset.abrirOb) {
    abrirDetalle(t.dataset.abrirOb);
    $('#detalle').scrollTop = 0;
  } else if (t.dataset.usarRespuesta) {
    const r = state.respuestas.find((x) => x.id === t.dataset.usarRespuesta);
    const form = $('#formCumplir');
    if (r && form) {
      form.nota.value = `Respuesta de ${r.remitente.replace(/\s*<.*$/, '')} (${fecha(r.recibido_at)}): ${(r.texto || '').slice(0, 1500)}`;
      if (r.carpeta_url) form.evidencia.value = r.carpeta_url;
      form.scrollIntoView({ behavior: 'smooth', block: 'center' });
      form.nota.focus();
      toast('Revisa el texto y pulsa "Guardar cumplimiento".');
    }
  } else if (t.dataset.revisarRespuesta) {
    const { error } = await sb.rpc('marcar_respuesta_revisada', { p_id: t.dataset.revisarRespuesta });
    if (error) { toast('No se pudo actualizar: ' + error.message); return; }
    const r = state.respuestas.find((x) => x.id === t.dataset.revisarRespuesta);
    if (r) { r.revisada = true; abrirDetalle(r.obligacion_id); renderLista(); renderCorreos(); }
  } else if (t.hasAttribute('data-toggle-correo')) {
    const card = t.closest('.correo');
    card.classList.toggle('open');
    t.textContent = card.classList.contains('open') ? 'Ocultar mensaje' : 'Ver mensaje';
  } else if (t.classList.contains('tl-item')) {
    abrirDetalle(t.dataset.id);
  } else if (t.classList.contains('al')) {
    abrirDrawer(false); abrirDetalle(t.dataset.id);
  } else if (t.hasAttribute('data-close')) {
    abrirDrawer(false);
  }
});
$('#detCerrar').addEventListener('click', () => $('#detalle').close());
$('#detalle').addEventListener('click', (ev) => { if (ev.target.id === 'detalle') ev.target.close(); });
$('#drawer').addEventListener('click', (ev) => { if (ev.target.id === 'drawer') abrirDrawer(false); });
document.addEventListener('keydown', (ev) => { if (ev.key === 'Escape') abrirDrawer(false); });
$('#btnAlertas').addEventListener('click', () => abrirDrawer(true));
$('#btnCalendario').addEventListener('click', descargarCalendario);
$('#btnEnviarCorreos').addEventListener('click', enviarCorreos);
$('#btnBandeja').addEventListener('click', () => abrirBandeja());
$('#btnVerUrgente').addEventListener('click', () => {
  state.estado = state.obligaciones.some((o) => o.estado === 'Vencida') ? 'Vencida' : 'Por vencer';
  render();
  $('#lista').scrollIntoView({ behavior: 'smooth', block: 'start' });
});
$('#btnNotif').addEventListener('click', async () => {
  const p = await Notification.requestPermission();
  actualizarBotonNotif();
  if (p === 'granted') { toast('Listo: verás avisos en este equipo cuando abras la app.'); notificarNavegador(); }
});
$('#btnLeidas').addEventListener('click', async () => {
  const { error } = await sb.rpc('marcar_alertas_leidas', { p_ids: null });
  if (error) { toast('No se pudo actualizar: ' + error.message); return; }
  await cargar(); renderAlertas(); toast('Avisos marcados como leídos.');
});
$('#buscar').addEventListener('input', (ev) => { state.q = ev.target.value; renderLista(); });

// ---------- inicio ----------
(async () => {
  actualizarBotonNotif();
  if (await cargar()) {
    render();
    notificarNavegador();
  }
  // Refresca cada 5 minutos si la pestaña queda abierta
  setInterval(async () => { if (await cargar()) { render(); notificarNavegador(); } }, 5 * 60 * 1000);
})();
