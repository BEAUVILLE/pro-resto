/* DIGIY RESTO — mémoire PRO officielle
   Rôle : mémoire locale commune pour ACTION RESTO / Calendrier / Cockpit.
   Doctrine : RESTO prépare la réservation ou le message client. Le restaurant vérifie et valide. Rien n'est confirmé automatiquement.
*/
(function(){
  "use strict";

  var VERSION = "resto-pro-memory-official-20260606";
  var NS = "DIGIY_RESTO_PRO";
  var KEYS = {
    session: NS + "_SESSION",
    reservations: "DIGIY_RESTO_RESERVATIONS",
    latest: "DIGIY_RESTO_ACTION_LATEST",
    notes: NS + "_NOTES",
    payDrafts: NS + "_PAY_DRAFTS"
  };

  function now(){ return new Date().toISOString(); }
  function id(prefix){ return String(prefix || "resto") + "_" + Date.now() + "_" + Math.random().toString(16).slice(2,8); }
  function read(key, fallback){ try{ var raw = localStorage.getItem(key); return raw ? JSON.parse(raw) : fallback; }catch(_){ return fallback; } }
  function write(key, value){ try{ localStorage.setItem(key, JSON.stringify(value)); return true; }catch(_){ return false; } }
  function list(key){ var rows = read(key, []); return Array.isArray(rows) ? rows : []; }
  function txt(v){ return String(v || "").trim(); }
  function norm(v){ return String(v || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g,""); }
  function amountFrom(v){ var m = String(v || "").replace(/\s+/g," ").match(/(?:acompte\s*)?(\d[\d\s.,]*)\s*(?:f|fcfa|xof)?/i); if(!m) return 0; var n = Number(String(m[1]).replace(/[^\d]/g,"")); return Number.isFinite(n) && n > 0 ? n : 0; }
  function channelFrom(v){ var t = norm(v); if(t.indexOf("wave") >= 0) return "Wave"; if(t.indexOf("orange") >= 0) return "Orange Money"; if(t.indexOf("carte") >= 0) return "Carte"; if(t.indexOf("cash") >= 0 || t.indexOf("espece") >= 0 || t.indexOf("espèce") >= 0) return "Cash"; return ""; }
  function today(){ return new Date().toISOString().slice(0,10); }

  function rowKey(row){ return String(row && (row.id || row.reference || [row.booking_date || row.date, row.booking_time || row.time, row.client_name || row.client, row.guests || row.people].join("|")) || id("tmp")); }
  function dedupe(rows, limit){
    var seen = {};
    return (Array.isArray(rows) ? rows : []).filter(function(row){
      var key = rowKey(row);
      if(seen[key]) return false;
      seen[key] = true;
      return true;
    }).slice(0, Number(limit || 180));
  }

  function normalizeReservation(input){
    var r = input && typeof input === "object" ? input : {note:txt(input)};
    var raw = txt(r.raw_text || r.note || r.message || r.table_note || "");
    var created = r.created_at || r.createdAt || now();
    var amount = Number(r.amount || r.price_fcfa || amountFrom(raw) || 0) || 0;
    return Object.assign({}, r, {
      id: r.id || r.reference || id("resto_resa"),
      module: "RESTO",
      source: r.source || "DIGIY_RESTO_PRO_MEMORY",
      status: r.status || "pending",
      client_name: r.client_name || r.client || r.customer_name || "Client RESTO",
      client_phone: r.client_phone || r.phone || "",
      booking_date: String(r.booking_date || r.date || today()).slice(0,10),
      booking_time: String(r.booking_time || r.time || "").slice(0,5),
      guests: Number(r.guests || r.people || r.guests_count || 1) || 1,
      table_note: r.table_note || r.note_text || r.note || "À attribuer",
      amount: amount,
      channel: r.channel || channelFrom(raw),
      note: raw || r.note || "",
      raw_text: raw || r.raw_text || "",
      created_at: created,
      createdAt: r.createdAt || created,
      updated_at: now(),
      validation_required: r.validation_required !== false,
      requiresHumanValidation: r.requiresHumanValidation !== false,
      safety: Object.assign({
        noAutoConfirmation: true,
        noAutoPayment: true,
        restaurantValidationRequired: true,
        humanValidationRequired: true
      }, r.safety || {})
    });
  }

  function saveReservation(input){
    var row = normalizeReservation(input);
    var rows = list(KEYS.reservations);
    rows.unshift(row);
    write(KEYS.reservations, dedupe(rows, 180));
    write(KEYS.latest, row);
    try{ window.dispatchEvent(new CustomEvent("digiy:resto:reservation-saved", {detail:row})); }catch(_){ }
    return row;
  }
  function saveNote(input){
    var row = normalizeReservation(input);
    row.kind = "Note RESTO";
    var rows = list(KEYS.notes);
    rows.unshift(row);
    write(KEYS.notes, dedupe(rows, 120));
    write(KEYS.latest, row);
    try{ window.dispatchEvent(new CustomEvent("digiy:resto:note-saved", {detail:row})); }catch(_){ }
    return row;
  }
  function savePayDraft(input){
    var row = normalizeReservation(input);
    row.target = "PAY";
    row.payType = "income";
    row.category = "Acompte RESTO";
    row.status = "draft_validated_by_restaurant";
    var rows = list(KEYS.payDrafts);
    rows.unshift(row);
    write(KEYS.payDrafts, dedupe(rows, 120));
    try{ localStorage.setItem("DIGIY_PAY_PENDING_MOVEMENT", JSON.stringify({
      id: row.id,
      source: "RESTO",
      module: "RESTO",
      target: "PAY",
      route: "PAY",
      status: "draft_validated_by_restaurant",
      text: row.note || row.raw_text || "Acompte RESTO",
      note: row.note || row.raw_text || "Acompte RESTO",
      amount: row.amount || null,
      currency: row.amount ? "XOF" : "",
      channel: row.channel || "Wave",
      who: row.client_name || "Client RESTO",
      payType: "income",
      type: "income",
      typeLabel: "Recette",
      category: "Acompte RESTO",
      createdAt: now(),
      requiresHumanValidation: true,
      safety: {noAutoPayment:true,noAutoConfirmation:true,humanValidationRequired:true}
    })); }catch(_){ }
    try{ window.dispatchEvent(new CustomEvent("digiy:resto:pay-draft-saved", {detail:row})); }catch(_){ }
    return row;
  }
  function rememberSession(session){
    var row = Object.assign({}, session || {}, {module:"RESTO", source:"DIGIY_RESTO_PRO_MEMORY", updated_at:now()});
    write(KEYS.session, row);
    return row;
  }
  function clear(kind){
    var map = {reservations:KEYS.reservations, notes:KEYS.notes, pay:KEYS.payDrafts, payDrafts:KEYS.payDrafts};
    if(!map[kind]) return false;
    write(map[kind], []);
    return true;
  }

  var API = {
    version: VERSION,
    keys: Object.assign({}, KEYS),
    rememberSession: rememberSession,
    session: function(){ return read(KEYS.session, {}); },
    normalizeReservation: normalizeReservation,
    saveReservation: saveReservation,
    saveBooking: saveReservation,
    reservations: function(){ return list(KEYS.reservations); },
    bookings: function(){ return list(KEYS.reservations); },
    latest: function(){ return read(KEYS.latest, null); },
    saveNote: saveNote,
    notes: function(){ return list(KEYS.notes); },
    savePayDraft: savePayDraft,
    payDrafts: function(){ return list(KEYS.payDrafts); },
    clear: clear
  };

  window.DIGIY_RESTO_PRO_MEMORY = API;
  window.DIGIY_RESTO_MEMORY = window.DIGIY_RESTO_MEMORY || API;
  try{ window.dispatchEvent(new CustomEvent("digiy:resto-pro-memory-ready", {detail:{version:VERSION}})); }catch(_){ }
})();
