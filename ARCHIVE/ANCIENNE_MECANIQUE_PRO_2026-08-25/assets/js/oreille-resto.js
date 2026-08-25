/* DIGIY RESTO — Oreille métier officielle
   Rôle : moteur vocal RESTO pour oreille.html.
   Doctrine : DIGIY prépare un message / une demande. Le restaurant vérifie et valide. Rien n'est confirmé automatiquement.
*/
(function(){
  "use strict";

  var VERSION = "oreille-resto-official-20260606";

  function $(id){ return document.getElementById(id); }
  function text(v){ return String(v || "").trim(); }
  function norm(v){ return String(v || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g,""); }
  function toast(message){
    var t = $("toast");
    if(!t) return;
    t.textContent = message;
    t.style.display = "block";
    setTimeout(function(){ t.style.display = "none"; }, 2200);
  }

  function sessionOk(){
    var keys = [
      "digiy_resto_session",
      "DIGIY_RESTO_SESSION",
      "DIGIY_SESSION_RESTO",
      "digiy_resto_guard_session",
      "digiy_guard_resto_session",
      "DIGIY_ACCESS"
    ];
    for(var i=0;i<keys.length;i++){
      try{
        var raw = localStorage.getItem(keys[i]) || sessionStorage.getItem(keys[i]);
        if(!raw) continue;
        var v = JSON.parse(raw);
        var ok = v && (v.access_ok === true || v.access === true || v.ok === true || v.pin_session_ok === true || v.preview === false);
        var sameModule = !v.module || String(v.module).toUpperCase() === "RESTO";
        var exp = Number(v.expires_at || v.expiresAt || 0);
        if(ok && sameModule && (!exp || Date.now() < exp)) return true;
      }catch(_){ }
    }
    return false;
  }

  function amountFrom(raw){
    var m = String(raw || "").replace(/\s+/g," ").match(/(\d[\d\s.,]*)\s*(?:f|fcfa|xof)?/i);
    if(!m) return 0;
    var n = Number(String(m[1]).replace(/[^\d]/g,""));
    return Number.isFinite(n) && n > 0 ? n : 0;
  }

  function extract(raw){
    var source = text(raw);
    var low = norm(source);
    var nums = source.match(/\b\d+[\s.]?\d*\b/g) || [];
    var amount = /acompte|wave|cash|orange|carte/.test(low) ? amountFrom(source) : 0;
    var mode = low.indexOf("wave") > -1 ? "Wave" : low.indexOf("cash") > -1 || low.indexOf("espece") > -1 ? "Cash" : low.indexOf("orange") > -1 ? "Orange Money" : low.indexOf("carte") > -1 ? "Carte" : "à vérifier";
    var place = low.indexOf("terrasse") > -1 ? "terrasse" : low.indexOf("salle") > -1 ? "salle" : low.indexOf("emporter") > -1 || low.indexOf("à emporter") > -1 ? "à emporter" : "à préciser";
    var kind = low.indexOf("commande") > -1 || low.indexOf("emporter") > -1 ? "commande" : "réservation";
    return {kind:kind, nums:nums.join(", ") || "à vérifier", amount:amount, mode:mode, place:place};
  }

  function buildMessage(raw){
    var x = extract(raw);
    return [
      "Bonjour,",
      "Nous avons bien noté votre demande RESTO.",
      "",
      text(raw),
      "",
      "Repères à vérifier :",
      "• Type : " + x.kind,
      "• Lieu / table : " + x.place,
      "• Chiffres / montant / personnes : " + x.nums,
      "• Paiement évoqué : " + x.mode + (x.amount ? " · " + x.amount.toLocaleString("fr-FR") + " F" : ""),
      "",
      "Le restaurant vérifie les détails avant confirmation.",
      "Rien n’est confirmé automatiquement.",
      "",
      "DIGIY RESTO : message préparé. Validation humaine obligatoire."
    ].join("\n");
  }

  function saveLatest(raw, msg){
    var payload = {
      id: "resto_oreille_" + Date.now() + "_" + Math.random().toString(16).slice(2,8),
      source: "OREILLE_RESTO",
      module: "RESTO",
      raw: text(raw),
      raw_text: text(raw),
      msg: msg,
      message: msg,
      preparedAt: new Date().toISOString(),
      created_at: new Date().toISOString(),
      validation_required: true,
      requiresHumanValidation: true,
      safety: {noAutoConfirmation:true,noAutoPayment:true,humanValidationRequired:true}
    };
    try{ localStorage.setItem("DIGIY_RESTO_OREILLE_LATEST", JSON.stringify(payload)); }catch(_){ }
    try{ localStorage.setItem("DIGIY_RESTO_ACTION_LATEST", JSON.stringify(payload)); }catch(_){ }
    try{
      if(window.DIGIY_RESTO_PRO_MEMORY && typeof window.DIGIY_RESTO_PRO_MEMORY.saveNote === "function"){
        window.DIGIY_RESTO_PRO_MEMORY.saveNote(payload);
      }
    }catch(_){ }
    try{ window.dispatchEvent(new CustomEvent("digiy:resto:oreille-prepared", {detail:payload})); }catch(_){ }
    return payload;
  }

  function prepare(){
    var input = $("txt");
    var output = $("msg");
    if(!input || !output) return null;
    var raw = text(input.value);
    if(!raw){ toast("Écris ou parle une demande RESTO"); return null; }
    var msg = buildMessage(raw);
    output.textContent = msg;
    var payload = saveLatest(raw, msg);
    toast("Message RESTO préparé");
    return payload;
  }

  function copyMessage(){
    prepare();
    var msg = $("msg") ? $("msg").textContent : "";
    try{
      if(navigator.clipboard){ navigator.clipboard.writeText(msg); toast("Copié"); return; }
    }catch(_){ }
    window.prompt("Copie le message :", msg);
  }

  function speakMessage(){
    prepare();
    try{
      speechSynthesis.cancel();
      var u = new SpeechSynthesisUtterance($("msg") ? $("msg").textContent : "");
      u.lang = "fr-FR";
      u.rate = 0.96;
      speechSynthesis.speak(u);
    }catch(_){ toast("Lecture indisponible"); }
  }

  function listen(){
    var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    if(!SR){ toast("Micro non disponible"); return; }
    var input = $("txt");
    var r = new SR();
    r.lang = "fr-FR";
    r.continuous = false;
    r.interimResults = false;
    r.maxAlternatives = 1;
    r.onresult = function(e){
      if(input){ input.value = e.results[0][0].transcript; }
      prepare();
    };
    r.onerror = function(){ toast("Micro fragile"); };
    r.start();
    toast("Micro ouvert");
  }

  function bind(){
    if(!sessionOk()){
      location.replace("./pin.html");
      return;
    }
    var prep = $("prep"), copy = $("copy"), speak = $("speak"), listenBtn = $("listen");
    if(prep) prep.onclick = prepare;
    if(copy) copy.onclick = copyMessage;
    if(speak) speak.onclick = speakMessage;
    if(listenBtn) listenBtn.onclick = listen;
  }

  window.DIGIY_RESTO_OREILLE = {
    version: VERSION,
    sessionOk: sessionOk,
    extract: extract,
    buildMessage: buildMessage,
    prepare: prepare,
    copyMessage: copyMessage,
    speakMessage: speakMessage,
    listen: listen,
    bind: bind
  };

  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", bind);
  else bind();
})();
