(function () {
  // Der Plan-Code steht im data-Attribut des <body>; das Skript selbst ist
  // fuer alle Plaene gleich und wird statisch ausgeliefert.
  var token = document.body.getAttribute('data-token') || '';
  var area = document.getElementById('points');
  var status = document.getElementById('status');
  var button = document.getElementById('save');
  var count = document.getElementById('count');
  var mapBox = document.getElementById('map');
  var mapHint = document.getElementById('map-hint');
  var summary = document.getElementById('summary');
  var list = document.getElementById('pointlist');
  var undoButton = document.getElementById('undo');
  var reverseButton = document.getElementById('reverse');
  var searchForm = document.getElementById('search');
  var searchInput = document.getElementById('q');
  var searchButton = document.getElementById('search-btn');
  var searchStatus = document.getElementById('search-status');
  var resultList = document.getElementById('results');
  var codeEl = document.getElementById('code');
  var planUrlEl = document.getElementById('plan-url');
  var qrImage = document.getElementById('qr');
  var gpxLink = document.getElementById('gpx');
  var draftBox = document.getElementById('draft');
  var draftText = document.getElementById('draft-text');
  var draftUse = document.getElementById('draft-use');
  var draftDrop = document.getElementById('draft-drop');
  var searchBusy = false;
  function show(text, cls) { status.textContent = text; status.className = cls || ''; }
  function parse(text) {
    var points = [];
    text.split(/\r?\n/).forEach(function (line, index) {
      var trimmed = line.trim();
      if (!trimmed) return;
      var parts = trimmed.split(',');
      if (parts.length < 2) throw new Error('Zeile ' + (index + 1) + ': Breite und Länge fehlen');
      var lat = Number(parts[0]);
      var lon = Number(parts[1]);
      if (!isFinite(lat) || lat < -90 || lat > 90) throw new Error('Zeile ' + (index + 1) + ': Breite ungültig');
      if (!isFinite(lon) || lon < -180 || lon > 180) throw new Error('Zeile ' + (index + 1) + ': Länge ungültig');
      var label = parts.slice(2).join(',').trim();
      points.push({ lat: lat, lon: lon, label: label || ('Wegpunkt ' + (points.length + 1)) });
    });
    return points;
  }
  // ---- Karte: Klick setzt einen Punkt, Ziehen verschiebt ihn.
  // Die Textzeilen bleiben die Wahrheit: jede Kartenaktion schreibt sie neu,
  // und Tippen im Textfeld zeichnet die Marker nach.
  var map = null;
  var markerLayer = null;
  var routeLine = null;
  var lastCount = -1;
  var writeGuard = false;
  var editTimer = null;
  // Automatisches Speichern: kurz nach der letzten Aenderung, damit
  // Klickarbeit nicht verloren geht, aber nicht bei jedem einzelnen Klick.
  var autosaveTimer = null;
  var unsaved = false;
  var saving = false;
  // Zaehlt Aenderungen: unterscheidet "waehrend des Speicherns etwas
  // dazugekommen" von "das Speichern ist fehlgeschlagen".
  var editSeq = 0;
  var AUTOSAVE_MS = 800;
  // Lokaler Entwurf: liegt unter einem Schluessel pro Code im Browser und
  // ueberlebt Reload, Absturz und einen abgelaufenen Code.
  var DRAFT_PREFIX = 'motoroute.plan.';
  var DRAFT_VERSION = 1;
  // Rettung: der neue Code entsteht erst beim ersten 404, danach wird er
  // gemerkt, damit ein zweiter Versuch nicht noch einen Code anlegt.
  var rescueToken = null;
  var rescuing = false;
  // Rueckgaengig: die letzten Zustaende der Punkte, nicht nur der letzte
  // Punkt. Jede Aenderung legt den Stand davor ab, Undo stellt ihn wieder her.
  var UNDO_LIMIT = 30;
  var undoStack = [];
  var undoing = false;
  var lastPoints = null;

  function pointLine(p) {
    return p.lat.toFixed(5) + ', ' + p.lon.toFixed(5) + ', ' + p.label;
  }

  function samePoints(a, b) {
    if (!a || !b || a.length !== b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (pointLine(a[i]) !== pointLine(b[i])) return false;
    }
    return true;
  }

  function clonePoints(points) {
    return points.map(function (p) {
      return { lat: p.lat, lon: p.lon, label: p.label, detail: p.detail };
    });
  }

  function updateUndoButton() {
    if (!undoButton) return;
    var entry = undoStack[undoStack.length - 1];
    undoButton.disabled = !entry;
    undoButton.title = entry ? 'Rückgängig: ' + entry.label : 'Nichts rückgängig zu machen';
    undoButton.setAttribute('aria-label', undoButton.title);
  }

  // Stand VOR einer Aenderung ablegen. Die Obergrenze haelt den Speicher
  // klein; 30 Schritte reichen fuer eine Klick-Sitzung.
  function pushUndo(points, label) {
    if (!points) return;
    undoStack.push({ points: clonePoints(points), label: label || 'Änderung' });
    if (undoStack.length > UNDO_LIMIT) undoStack.shift();
    updateUndoButton();
  }

  function draftStorage() {
    try { return window.localStorage; } catch (err) { return null; }
  }

  function draftKey(forToken) {
    return DRAFT_PREFIX + (forToken || token);
  }

  // Nach jeder Aenderung mitschreiben - auch wenn das Speichern noch wartet
  // oder gerade scheitert.
  function saveDraft(points, forToken) {
    var store = draftStorage();
    if (!store || !points || !points.length) return;
    try {
      store.setItem(draftKey(forToken), JSON.stringify({
        version: DRAFT_VERSION,
        at: Date.now(),
        points: points
      }));
    } catch (err) { /* privater Modus oder voller Speicher: kein Weltuntergang */ }
  }

  function clearDraft(forToken) {
    var store = draftStorage();
    if (!store) return;
    try { store.removeItem(draftKey(forToken)); } catch (err) { /* egal */ }
  }

  function readDraft() {
    var store = draftStorage();
    if (!store) return null;
    var raw = null;
    try { raw = store.getItem(draftKey()); } catch (err) { return null; }
    if (!raw) return null;
    var draft = null;
    try { draft = JSON.parse(raw); } catch (err) { draft = null; }
    if (!draft || draft.version !== DRAFT_VERSION || !Array.isArray(draft.points) ||
      !draft.points.length) {
      clearDraft();
      return null;
    }
    return draft;
  }

  function formatClock(at) {
    try {
      return new Date(at).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
    } catch (err) { return ''; }
  }

  function hideDraftBox() {
    if (draftBox) draftBox.hidden = true;
  }

  // "Entwurf fortsetzen?": nur anbieten, wenn der lokale Stand vom Server
  // abweicht - sonst waere es ein Nichts-Tun.
  function offerDraft() {
    if (!draftBox || !draftText || !draftUse || !draftDrop) return;
    var draft = readDraft();
    if (!draft) return;
    if (samePoints(draft.points, readPoints() || [])) { clearDraft(); return; }
    draftText.textContent = 'Lokal liegt ein Entwurf von ' + formatClock(draft.at) + ' mit ' +
      draft.points.length + (draft.points.length === 1 ? ' Punkt' : ' Punkten') + '.';
    draftBox.hidden = false;
    draftUse.onclick = function () {
      hideDraftBox();
      writePoints(draft.points, 'Entwurf übernommen - wird jetzt gespeichert.');
    };
    draftDrop.onclick = function () {
      clearDraft();
      hideDraftBox();
      show('Entwurf verworfen.', 'ok');
    };
  }

  function readPoints() {
    try { return parse(area.value); } catch (err) { return null; }
  }

  // Luftlinie zwischen zwei Punkten (Haversine, Erdradius 6371,0088 km).
  // Bewusst ohne Routingdienst: die Linie ist eine Lesehilfe fuer die
  // Reihenfolge, keine berechnete Strassenstrecke.
  function distanceKm(a, b) {
    var rad = Math.PI / 180;
    var dLat = (b.lat - a.lat) * rad;
    var dLon = (b.lon - a.lon) * rad;
    var s = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return 2 * 6371.0088 * Math.asin(Math.sqrt(s));
  }

  function formatKm(km) {
    if (km < 1) return Math.round(km * 1000) + ' m';
    return km.toFixed(1).replace('.', ',') + ' km';
  }

  function updateSummary(points) {
    if (!summary) return;
    if (!points.length) { summary.textContent = 'Noch keine Punkte.'; return; }
    var parts = [points.length === 1 ? '1 Punkt' : points.length + ' Punkte'];
    if (points.length > 1) {
      var km = 0;
      for (var i = 1; i < points.length; i += 1) km += distanceKm(points[i - 1], points[i]);
      parts.push('Luftlinie ' + formatKm(km));
    }
    summary.textContent = parts.join(' · ');
  }

  // Linie in der Reihenfolge der Punkte: zeigt sofort, wenn die Tour
  // zickzackt. interactive: false, damit sie keine Klicks auf die Karte
  // abfaengt. Laeuft auch beim Drag mit, dort werden die Marker nicht neu
  // aufgebaut.
  function syncRoute(points) {
    updateSummary(points);
    if (routeLine) {
      routeLine.setLatLngs(points.map(function (p) { return [p.lat, p.lon]; }));
    }
  }

  // Punktliste unter der Karte: Nummer, Name, hoch/runter/loeschen. Sie ist
  // die einzige Moeglichkeit, die Reihenfolge zu aendern - Marker ziehen
  // verschiebt nur die Lage eines Punktes.
  function listButton(text, title, disabled, action) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'smallbtn';
    button.textContent = text;
    button.title = title;
    button.setAttribute('aria-label', title);
    if (disabled) { button.disabled = true; } else { button.addEventListener('click', action); }
    return button;
  }

  function renderList(points) {
    if (!list) return;
    list.innerHTML = '';
    points.forEach(function (p, index) {
      var row = document.createElement('li');
      var isStart = index === 0;
      var isEnd = points.length > 1 && index === points.length - 1;
      var nr = document.createElement('span');
      // Dieselbe Einordnung wie auf der Karte: erster Punkt gruen, letzter
      // rot. Die Reihenfolge selbst bestimmt weiterhin allein die Liste.
      nr.className = 'nr' + (isStart ? ' start' : '') + (isEnd ? ' end' : '');
      nr.title = isStart ? 'Start' : isEnd ? 'Ziel' : 'Wegpunkt ' + (index + 1);
      nr.textContent = String(index + 1);
      var name = document.createElement('input');
      name.type = 'text';
      name.className = 'name';
      name.value = p.label;
      name.setAttribute('aria-label', 'Name von Punkt ' + (index + 1));
      name.addEventListener('change', function () { renamePoint(index, name.value, name); });
      name.addEventListener('keydown', function (event) {
        // Enter uebernimmt sofort: auf das change-Event beim Blur allein ist
        // kein Verlass (z. B. wenn der Wert programmatisch gesetzt wurde).
        if (event.key === 'Enter') { event.preventDefault(); renamePoint(index, name.value, name); }
      });
      row.appendChild(nr);
      row.appendChild(name);
      // Etappe bis zum naechsten Punkt: dieselbe Luftlinie wie die
      // Zusammenfassung, nur pro Zeile - so laesst sich abschaetzen, wie
      // lang ein Tagesabschnitt wird. Die letzte Zeile hat keinen Nachfolger.
      if (index < points.length - 1) {
        var leg = document.createElement('span');
        leg.className = 'leg';
        leg.textContent = '→ ' + formatKm(distanceKm(p, points[index + 1]));
        leg.title = 'Luftlinie zum nächsten Punkt';
        row.appendChild(leg);
      }
      row.appendChild(listButton('▲', 'Nach oben', index === 0, function () { movePoint(index, -1); }));
      row.appendChild(listButton('▼', 'Nach unten', index === points.length - 1, function () { movePoint(index, 1); }));
      row.appendChild(listButton('×', 'Punkt löschen', false, function () { removePoint(index); }));
      list.appendChild(row);
    });
    // Der Undo-Knopf haengt am Stapel (updateUndoButton), nicht an der
    // Punktzahl: auch Loeschen, Umdrehen und Ziehen sind Schritte.
    // Umdrehen braucht zwei Punkte, sonst waere es ein Nichts-Tun.
    if (reverseButton) reverseButton.disabled = points.length < 2;
  }

  // Umbenennen: nur das Label tauschen, Koordinaten und Reihenfolge bleiben.
  // Leerer Name wird verworfen (sonst hätte der Punkt keinen Namen mehr).
  function renamePoint(index, raw, field) {
    var current = readPoints() || [];
    var old = current[index];
    if (!old) return;
    var name = raw === undefined || raw === null ? '' : String(raw).trim();
    if (!name) {
      // Leerer Name: Feld auf den gespeicherten Namen zuruecksetzen, statt
      // einen namenlosen Punkt zu erzeugen.
      if (field) field.value = old.label;
      return;
    }
    if (name === old.label) return;
    current[index] = {
      lat: old.lat,
      lon: old.lon,
      label: name,
      detail: old.detail
    };
    writePoints(current, 'Punkt umbenannt: ' + name, undefined, 'Punkt umbenannt');
  }

  function movePoint(index, step) {
    var current = readPoints() || [];
    var target = index + step;
    if (target < 0 || target >= current.length) return;
    var swapped = current[index];
    current[index] = current[target];
    current[target] = swapped;
    writePoints(current, 'Reihenfolge geändert.', undefined, 'Reihenfolge geändert');
  }

  function removePoint(index) {
    var current = readPoints() || [];
    if (index < 0 || index >= current.length) return;
    current.splice(index, 1);
    if (map) map.closePopup();
    writePoints(current, 'Punkt gelöscht.', undefined, 'Punkt gelöscht');
  }

  // Hin- und Rueckweg: dieselben Punkte in umgekehrter Reihenfolge. Der
  // Rest haengt an der Reihenfolge und zieht automatisch mit - Start/Ziel
  // (Farben in Liste und Marker), Etappen und die Textzeilen.
  function reversePoints() {
    var current = readPoints() || [];
    if (current.length < 2) return;
    current.reverse();
    writePoints(current, 'Reihenfolge umgedreht - Ziel ist jetzt Start.', undefined, 'Umdrehen');
  }

  // Rueckgaengig ueber die letzten Zustaende: Loeschen (Liste und Popup),
  // Umdrehen, Ziehen, Umbenennen und Tippen legen jeweils den Stand davor ab.
  function undo() {
    var entry = undoStack.pop();
    if (!entry) { updateUndoButton(); return; }
    // Ein Undo schreibt selbst keinen neuen Schritt in den Stapel, sonst
    // liesse es sich endlos hin und her schalten.
    undoing = true;
    try {
      writePoints(entry.points, 'Rückgängig gemacht: ' + entry.label + '.');
    } finally {
      undoing = false;
    }
    updateUndoButton();
  }

  // ---- Ortssuche: laeuft ueber das eigene Backend (eigener User-Agent,
  // Cache, 1 Nominatim-Anfrage pro Sekunde). Ein Treffer setzt den Punkt
  // genau wie ein Kartenklick.
  function setSearchStatus(text, cls) {
    if (!searchStatus) return;
    searchStatus.textContent = text;
    searchStatus.className = 'muted' + (cls ? ' ' + cls : '');
  }

  function clearResults() {
    if (resultList) resultList.innerHTML = '';
  }

  function addFromSearch(result) {
    var current = readPoints() || [];
    current.push({ lat: result.lat, lon: result.lon, label: result.label });
    writePoints(current, 'Punkt "' + result.label + '" aus der Suche übernommen.', undefined, 'Punkt aus der Suche');
    if (map) map.setView([result.lat, result.lon], 12);
    clearResults();
    setSearchStatus('');
  }

  function renderResults(results) {
    clearResults();
    if (!results.length) {
      setSearchStatus('Nichts gefunden - anderen Namen probieren?', 'err');
      return;
    }
    results.forEach(function (result) {
      var row = document.createElement('li');
      var button = document.createElement('button');
      button.type = 'button';
      var main = document.createElement('span');
      main.textContent = result.label;
      var sub = document.createElement('span');
      sub.className = 'sub';
      sub.textContent = result.detail || (result.lat.toFixed(4) + ', ' + result.lon.toFixed(4));
      button.appendChild(main);
      button.appendChild(sub);
      button.addEventListener('click', function () { addFromSearch(result); });
      row.appendChild(button);
      resultList.appendChild(row);
    });
    setSearchStatus(results.length + ' Treffer - Auswahl setzt den Punkt und springt hin.');
  }

  function searchErrorText(status, data) {
    var message = data && data.message ? [].concat(data.message).join(' ') : '';
    if (status === 429) return 'Zu viele Suchen - bitte einen Moment warten.';
    if (status === 400) return message || 'Suchbegriff prüfen.';
    if (status === 404) return 'Dieser Plan ist abgelaufen - beim Speichern wird automatisch ein neuer Code angelegt.';
    return message || 'Ortssuche gerade nicht erreichbar - bitte später erneut versuchen.';
  }

  if (searchForm) {
    searchForm.addEventListener('submit', function (event) {
      event.preventDefault();
      if (searchBusy) return;
      var query = (searchInput.value || '').trim();
      if (query.length < 3) {
        setSearchStatus('Bitte mindestens 3 Zeichen eingeben (z. B. Eibsee).', 'err');
        return;
      }
      searchBusy = true;
      if (searchButton) searchButton.disabled = true;
      clearResults();
      setSearchStatus('Suche läuft …');
      fetch('/api/v1/pairing/' + token + '/geocode?q=' + encodeURIComponent(query))
        .then(function (res) {
          return res.json().catch(function () { return null; }).then(function (data) {
            return { status: res.status, data: data };
          });
        })
        .then(function (out) {
          if (out.status === 200 && out.data && Array.isArray(out.data.results)) {
            renderResults(out.data.results);
            return;
          }
          setSearchStatus(searchErrorText(out.status, out.data), 'err');
        })
        .catch(function () {
          setSearchStatus('Server nicht erreichbar. Verbindung prüfen und erneut versuchen.', 'err');
        })
        .then(function () {
          searchBusy = false;
          if (searchButton) searchButton.disabled = false;
        });
    });
  }

  function writePoints(points, message, redraw, undoLabel) {
    // Der Stand davor wandert in den Undo-Stapel - ausser wenn das Undo
    // selbst schreibt.
    if (!undoing) pushUndo(readPoints(), undoLabel || message);
    writeGuard = true;
    area.value = points.map(pointLine).join('\n');
    // Schon hier lokal sichern, nicht erst beim Speichern: der Entwurf ist
    // die Versicherung, wenn der Server nicht antwortet.
    saveDraft(points);
    writeGuard = false;
    lastPoints = points;
    syncRoute(points);
    // redraw === false laesst vorhandene Marker stehen (Fall: Marker gezogen -
    // der Marker sitzt nach dem Drag schon richtig, ein Neuaufbau waere nur
    // ein DOM-Teardown mitten in der laufenden Mausgeste).
    if (redraw !== false) drawMarkers(points);
    if (message) show(message, 'ok');
    scheduleAutosave();
  }

  // Speichert erst, wenn eine Weile nichts mehr passiert ist. Mehrere Klicks
  // hintereinander ergeben so einen einzigen Aufruf.
  function scheduleAutosave() {
    unsaved = true;
    editSeq += 1;
    clearTimeout(autosaveTimer);
    autosaveTimer = setTimeout(autosave, AUTOSAVE_MS);
  }

  function saveRequest(points, target) {
    return fetch('/api/v1/pairing/' + (target || token) + '/points', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ points: points })
    });
  }

  function startPlan() {
    return fetch('/api/v1/pairing/start', { method: 'POST' })
      .then(function (res) {
        if (!res.ok) throw new Error('Start fehlgeschlagen (' + res.status + ')');
        return res.json();
      })
      .then(function (out) {
        if (!out || !out.token) throw new Error('Kein Code erhalten');
        return String(out.token);
      });
  }

  // Alles, was am Code haengt, auf einmal umhaengen: Code-Zeile, Link zum
  // Abtippen, QR-Code, GPX-Download und Adresszeile. Ein Reload landet
  // dadurch beim neuen Code statt wieder auf der 404-Seite.
  function applyToken(newToken) {
    token = newToken;
    document.body.setAttribute('data-token', newToken);
    if (codeEl) codeEl.textContent = newToken;
    if (planUrlEl) planUrlEl.textContent = location.origin + '/plan/' + newToken;
    if (qrImage) qrImage.src = '/plan/' + newToken + '/qr.png';
    if (gpxLink) {
      gpxLink.href = '/plan/' + newToken + '/gpx';
      gpxLink.setAttribute('download', 'MotoRoute-' + newToken + '.gpx');
      gpxLink.textContent = 'MotoRoute-' + newToken + '.gpx';
    }
    try { window.history.replaceState(null, '', '/plan/' + newToken); } catch (err) { /* egal */ }
  }

  // Abgelaufener Code (404): neuen anlegen, Punkte hinueberretten, Seite
  // umhaengen. Scheitert das, bleibt der Entwurf im Browser - verloren ist
  // die Klickarbeit damit nicht.
  function rescueExpired(points) {
    if (rescuing) return;
    rescuing = true;
    unsaved = true;
    clearTimeout(autosaveTimer);
    autosaveTimer = null;
    show('Der Code ist abgelaufen - neuer Code wird angelegt …');
    var next = rescueToken ? Promise.resolve(rescueToken) : startPlan();
    next
      .then(function (newToken) {
        rescueToken = newToken;
        return saveRequest(points, newToken).then(function (res) {
          if (!res.ok) throw new Error('Speichern fehlgeschlagen (' + res.status + ')');
          return newToken;
        });
      })
      .then(function (newToken) {
        var oldToken = token;
        rescueToken = null;
        applyToken(newToken);
        clearDraft(oldToken);
        if (count) count.textContent = points.length;
        unsaved = !samePoints(readPoints() || [], points);
        if (unsaved) scheduleAutosave();
        show('Code ' + oldToken + ' war abgelaufen. Neuer Code ' + newToken +
          ' angelegt, deine Punkte sind übernommen - Link, QR und GPX zeigen auf den neuen Code.', 'ok');
      })
      .catch(function () {
        // Nichts mehr gegen den alten Code versuchen, sonst hagelt es 404s.
        saveDraft(points);
        show('Der Code ist abgelaufen und ein neuer konnte nicht angelegt werden. ' +
          'Deine Punkte liegen als Entwurf im Browser - Seite neu laden und „Entwurf fortsetzen“ wählen.', 'err');
      })
      .then(function () {
        rescuing = false;
      });
  }

  function autosave() {
    autosaveTimer = null;
    if (!unsaved || saving || rescuing) return;
    var points;
    try { points = parse(area.value); } catch (err) { return; }
    saving = true;
    var seq = editSeq;
    saveRequest(points)
      .then(function (res) {
        if (res.ok) {
          unsaved = false;
          clearDraft();
          if (count) count.textContent = points.length;
          show('Automatisch gespeichert.', 'ok');
          return;
        }
        if (res.status === 404) {
          rescueExpired(points);
          return;
        }
        show('Automatisches Speichern fehlgeschlagen (' + res.status + ') - bitte "Punkte speichern".', 'err');
      })
      .catch(function () {
        show('Server nicht erreichbar - noch nicht gespeichert.', 'err');
      })
      .then(function () {
        saving = false;
        // Nur nachziehen, wenn waehrend des Speicherns etwas dazukam. Ein
        // Fehlschlag wird bewusst nicht im 800-ms-Takt wiederholt.
        if (unsaved && editSeq !== seq) scheduleAutosave();
      });
  }

  // Beim Verlassen (Tab zu, neu laden, Link) nachfragen, solange etwas offen ist.
  window.addEventListener('beforeunload', function (event) {
    if (!unsaved) return;
    event.preventDefault();
    event.returnValue = 'Änderungen sind noch nicht gespeichert.';
    return event.returnValue;
  });

  function drawMarkers(points) {
    lastPoints = points;
    syncRoute(points);
    renderList(points);
    if (!markerLayer) return;
    markerLayer.clearLayers();
    points.forEach(function (p, index) {
      // Start gruen, Ziel rot: die Reihenfolge bleibt allein Sache der Liste,
      // die Farbe macht nur sichtbar, wo die Tour anfaengt und aufhoert. Bei
      // einem einzigen Punkt ist er beides - dann bleibt er gruen.
      var isStart = index === 0;
      var isEnd = points.length > 1 && index === points.length - 1;
      var marker = L.marker([p.lat, p.lon], {
        draggable: true,
        keyboard: false,
        title: isStart ? 'Start' : isEnd ? 'Ziel' : 'Wegpunkt ' + (index + 1),
        // Nummerierter Pin: die Zahl ist die Position in der Tour und macht
        // Reihenfolge-Fehler sofort sichtbar.
        icon: L.divIcon({
          className: 'numbered-pin' + (isStart ? ' start' : '') + (isEnd ? ' end' : ''),
          html: '<span>' + (index + 1) + '</span>',
          iconSize: [26, 26],
          iconAnchor: [13, 13]
        })
      }).addTo(markerLayer);
      var box = document.createElement('div');
      var title = document.createElement('input');
      title.type = 'text';
      title.className = 'popup-name';
      title.value = p.label;
      title.setAttribute('aria-label', 'Name von Punkt ' + (index + 1));
      title.addEventListener('change', function () { renamePoint(index, title.value, title); });
      title.addEventListener('keydown', function (event) {
        if (event.key === 'Enter') { event.preventDefault(); renamePoint(index, title.value, title); }
      });
      var remove = document.createElement('button');
      remove.type = 'button';
      remove.className = 'linkish';
      remove.textContent = 'Punkt entfernen';
      // Loeschen laeuft ueber dieselbe Funktion wie der ×-Knopf der Liste:
      // sonst fehlte hier die Statusmeldung und die beiden Wege koennten
      // auseinanderlaufen.
      remove.addEventListener('click', function () { removePoint(index); });
      box.appendChild(title);
      box.appendChild(document.createElement('br'));
      box.appendChild(remove);
      marker.bindPopup(box);
      marker.on('dragend', function () {
        var current = readPoints() || [];
        var moved = marker.getLatLng();
        var old = current[index];
        current[index] = {
          lat: moved.lat,
          lon: moved.lng,
          label: old ? old.label : 'Wegpunkt ' + (index + 1),
          detail: old ? old.detail : null
        };
        // Marker NICHT neu aufbauen: clearLayers() zerstoert hier genau das
        // Element, an dem der Browser den Drag gerade beendet - der naechste
        // Klick (z. B. auf "Punkte speichern") kann dadurch verschluckt werden.
        writePoints(current, 'Punkt verschoben - Zeile aktualisiert.', false, 'Verschieben');
      });
    });
    if (points.length && points.length !== lastCount) {
      lastCount = points.length;
      map.fitBounds(L.latLngBounds(points.map(function (p) { return [p.lat, p.lon]; })),
        { padding: [30, 30], maxZoom: 12 });
    }
  }

  function initMap() {
    if (!window.L || !mapBox) {
      if (mapHint) mapHint.textContent = 'Karte hier nicht verfügbar - Punkte wie gewohnt als Zeilen eintragen, das funktioniert genauso.';
      updateSummary(readPoints() || []);
      return;
    }
    map = L.map(mapBox, { scrollWheelZoom: false }).setView([47.6, 11.0], 8);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 18,
      attribution: '&copy; OpenStreetMap-Mitwirkende'
    }).addTo(map);
    markerLayer = L.layerGroup().addTo(map);
    routeLine = L.polyline([], { color: '#18181b', weight: 3, opacity: 0.7, interactive: false }).addTo(map);
    map.on('click', function (event) {
      var current = readPoints() || [];
      current.push({
        lat: event.latlng.lat,
        lon: event.latlng.lng,
        label: 'Wegpunkt ' + (current.length + 1)
      });
      writePoints(current, 'Punkt gesetzt - die Textzeile ist ergänzt.', undefined, 'Punkt gesetzt');
    });
    var initial = readPoints() || [];
    if (initial.length) drawMarkers(initial);
    // Auch ein leerer Plan fuellt die Zeile unter der Karte - sonst bliebe sie
    // bis zur ersten Aenderung leer stehen.
    else updateSummary(initial);
  }

  area.addEventListener('input', function () {
    if (writeGuard) return;
    clearTimeout(editTimer);
    editTimer = setTimeout(function () {
      var points = readPoints();
      if (!points) return;
      if (lastPoints && !samePoints(lastPoints, points)) {
        pushUndo(lastPoints, 'Textfeld geändert');
      }
      drawMarkers(points);
      saveDraft(points);
      show('', '');
      scheduleAutosave();
    }, 350);
  });

  button.addEventListener('click', function () {
    var points;
    try { points = parse(area.value); } catch (e) { show(e.message, 'err'); return; }
    button.disabled = true;
    show('Speichern …');
    saveRequest(points).then(function (res) {
      if (res.ok) {
        count.textContent = points.length;
        unsaved = false;
        clearDraft();
        clearTimeout(autosaveTimer);
        autosaveTimer = null;
        show(points.length + ' Punkt(e) gespeichert – in der App abholen.', 'ok');
      }
      else if (res.status === 404) { rescueExpired(points); }
      else { show('Speichern fehlgeschlagen (' + res.status + ').', 'err'); }
    }).catch(function () {
      show('Server nicht erreichbar. Verbindung prüfen und erneut versuchen.', 'err');
    }).then(function () { button.disabled = false; });
  });
initMap();
  offerDraft();
  updateUndoButton();
  if (undoButton) undoButton.addEventListener('click', undo);
  if (reverseButton) reverseButton.addEventListener('click', reversePoints);
})();
