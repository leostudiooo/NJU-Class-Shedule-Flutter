// Return the SEU term list in the common manual-term contract used by Flutter.
// The page only receives [{dm, name, start, selected, ...}], never the raw API tables.
(function() {
  const CONFIG = {
    APP_BASE: 'https://ehall.seu.edu.cn/jwapp/sys/bykb',
    CURRENT_TERM_API: '/modules/jshkcb/dqxnxq.do',
    TERM_LIST_API: '/modules/jshkcb/xnxqcx.do',
    SEMESTER_CALENDAR_API: '/modules/xskcb/cxxljc.do',
  };

  const buildUrl = (path) => {
    if (typeof WIS_EMAP_SERV !== 'undefined' && WIS_EMAP_SERV.getAbsPath) {
      return WIS_EMAP_SERV.getAbsPath(path);
    }
    return CONFIG.APP_BASE + path;
  };

  const encodeParams = (params = {}) => Object.keys(params)
    .map(key => encodeURIComponent(key) + '=' + encodeURIComponent(params[key]))
    .join('&');

  const syncRequest = (path, params = {}) => {
    const url = buildUrl(path);
    if (typeof BH_UTILS !== 'undefined' && BH_UTILS.doSyncAjax) {
      return BH_UTILS.doSyncAjax(url, params);
    }

    const xhr = new XMLHttpRequest();
    xhr.open('POST', url, false);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    xhr.setRequestHeader('Accept', 'application/json, text/javascript, */*; q=0.01');
    xhr.send(encodeParams(params));
    if (xhr.status !== 200) throw new Error('HTTP Error: ' + xhr.status);
    return JSON.parse(xhr.responseText);
  };

  const asObject = (value) => {
    if (typeof value !== 'string') return value || {};
    try { return JSON.parse(value); } catch (_) { return {}; }
  };

  const extractRows = (data, tableName) => {
    const object = asObject(data);
    return object && object.datas && object.datas[tableName] && object.datas[tableName].rows
      ? object.datas[tableName].rows
      : [];
  };

  const parseTermCode = (dm) => {
    const parts = String(dm || '').split('-');
    if (parts.length < 3) return null;
    return { xn: parts[0] + '-' + parts[1], xq: parts.slice(2).join('-') };
  };

  const normalizeDate = (value) => {
    const match = String(value || '').match(/\d{4}-\d{1,2}-\d{1,2}/);
    if (!match) return null;
    const parts = match[0].split('-');
    return parts[0] + '-' + parts[1].padStart(2, '0') + '-' + parts[2].padStart(2, '0');
  };

  const readCurrentTerm = () => {
    const injected = typeof window !== 'undefined'
      ? window.__course_import_selected_term__
      : null;
    if (injected && (injected.dm || injected.DM)) {
      return {
        dm: injected.dm || injected.DM,
        name: injected.name || injected.MC || '',
      };
    }

    try {
      const rows = extractRows(syncRequest(CONFIG.CURRENT_TERM_API), 'dqxnxq');
      if (rows.length > 0) {
        return { dm: rows[0].DM || '', name: rows[0].MC || '' };
      }
    } catch (_) {}
    return { dm: '', name: '' };
  };

  const readCalendar = (dm) => {
    const parts = parseTermCode(dm);
    if (!parts) return null;
    try {
      const rows = extractRows(syncRequest(CONFIG.SEMESTER_CALENDAR_API, {
        XN: parts.xn,
        XQ: parts.xq,
      }), 'cxxljc');
      return rows.length > 0 ? rows[0] : null;
    } catch (_) {
      return null;
    }
  };

  const selected = readCurrentTerm();
  const termRows = extractRows(
    syncRequest(CONFIG.TERM_LIST_API, { '*order': '-DM' }),
    'xnxqcx'
  );
  const terms = termRows.map(row => {
    const dm = row.DM || '';
    const parts = parseTermCode(dm);
    const calendar = readCalendar(dm);
    return {
      dm,
      name: row.MC || '',
      xn: parts ? parts.xn : row.XNDM || '',
      xq: parts ? parts.xq : row.XQDM || '',
      start: normalizeDate(calendar && calendar.XQKSRQ),
      weeks: calendar && calendar.ZZC != null ? calendar.ZZC : null,
      teachingWeeks: calendar && calendar.ZJXZC != null ? calendar.ZJXZC : null,
      selected: (selected.dm && selected.dm === dm) ||
        (!selected.dm && selected.name && selected.name === row.MC),
    };
  }).filter(term => term.dm);

  return encodeURIComponent(JSON.stringify(terms));
})()
