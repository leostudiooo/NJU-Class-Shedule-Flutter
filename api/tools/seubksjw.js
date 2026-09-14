function scheduleHtmlParser() {
  // 配置常量
  const CONFIG = {
    APP_BASE: 'https://ehall.seu.edu.cn/jwapp/sys/bykb',
    CURRENT_TERM_API: '/modules/jshkcb/dqxnxq.do',
    TERM_LIST_API: '/modules/jshkcb/xnxqcx.do',
    SCHEDULE_API: '/modules/xskcb/cxxszhxqkb.do',
    CURRENT_WEEK_API: '/modules/jshkcb/dqzc.do',
  };

  const buildUrl = (path) => {
    if (typeof WIS_EMAP_SERV !== 'undefined' && WIS_EMAP_SERV.getAbsPath) {
      return WIS_EMAP_SERV.getAbsPath(path);
    }
    return `${CONFIG.APP_BASE}${path}`;
  };

  const encodeParams = (params = {}) => {
    return Object.keys(params)
      .map(key => `${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`)
      .join('&');
  };

  // 同步请求，优先使用页面自己的 EMAP Ajax 封装
  const syncRequest = (path, params = {}) => {
    const url = buildUrl(path);

    if (typeof BH_UTILS !== 'undefined' && BH_UTILS.doSyncAjax) {
      return BH_UTILS.doSyncAjax(url, params);
    }

    const xhr = new XMLHttpRequest();
    xhr.open('POST', url, false); // 保持同步模式
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    xhr.setRequestHeader('Accept', 'application/json, text/javascript, */*; q=0.01');
    xhr.send(encodeParams(params));
    if (xhr.status !== 200) {
      throw new Error(`HTTP Error: ${xhr.status}`);
    }
    return JSON.parse(xhr.responseText);
  };

  const extractRows = (data, tableName) => {
    return data?.datas?.[tableName]?.rows || [];
  };

  const getJqxSelectedItem = (elementId) => {
    try {
      if (typeof $ === 'undefined' || !$(elementId).jqxDropDownList) return null;
      return $(elementId).jqxDropDownList('getSelectedItem');
    } catch (error) {
      return null;
    }
  };

  // 优先使用页面“更改学年学期”中已经选定的学期。
  const getSelectedTermFromDom = () => {
    const termEl = document.querySelector('#dqxnxq2');
    const selectedItem = getJqxSelectedItem('#dqxnxq2');
    const termCode =
      selectedItem?.value ||
      selectedItem?.originalItem?.DM ||
      termEl?.getAttribute('value') ||
      termEl?.value ||
      '';
    const termName =
      selectedItem?.label ||
      selectedItem?.originalItem?.MC ||
      termEl?.textContent?.trim() ||
      '';

    if (!termCode && !termName) return null;
    return { DM: termCode, MC: termName };
  };

  const fetchTermList = () => {
    const termListData = syncRequest(CONFIG.TERM_LIST_API, { '*order': '-DM' });
    return extractRows(termListData, 'xnxqcx');
  };

  // 获取学期：页面选择 > 当前学期接口 > 学期列表最新项
  const fetchTerm = () => {
    const selectedTerm = getSelectedTermFromDom();
    let termRows = [];

    try {
      termRows = fetchTermList();
    } catch (error) {
      termRows = [];
    }

    if (selectedTerm?.DM) {
      return termRows.find(term => term.DM === selectedTerm.DM) || selectedTerm;
    }

    if (selectedTerm?.MC) {
      const matchedByName = termRows.find(term => term.MC === selectedTerm.MC);
      if (matchedByName) return matchedByName;
    }

    try {
      const data = syncRequest(CONFIG.CURRENT_TERM_API);
      const rows = extractRows(data, 'dqxnxq');
      if (rows.length > 0) return rows[0];
    } catch (error) {
      // 继续回退学期列表
    }

    return termRows[0];
  };

  // 获取原始课表数据
  const fetchSchedule = (termCode) => {
    const data = syncRequest(CONFIG.SCHEDULE_API, {
      '*order': '+KSJC,+JSJC',
      XNXQDM: termCode,
    });
    return extractRows(data, 'cxxszhxqkb');
  };

  const parseTermCode = (termCode) => {
    const match = String(termCode || '').match(/^(\d{4}-\d{4})-(.+)$/);
    if (!match) return null;
    return { XN: match[1], XQ: match[2] };
  };

  const parseNumber = (value) => {
    const match = String(value ?? '').match(/\d+/);
    return match ? parseInt(match[0], 10) : null;
  };

  const createUtcDate = (year, month, day) => {
    return new Date(Date.UTC(year, month - 1, day));
  };

  const addDays = (date, days) => {
    const next = new Date(date.getTime());
    next.setUTCDate(next.getUTCDate() + days);
    return next;
  };

  const formatDate = (date) => {
    const y = date.getUTCFullYear();
    const m = String(date.getUTCMonth() + 1).padStart(2, '0');
    const d = String(date.getUTCDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  };

  const mondayOnOrAfter = (date) => {
    const day = date.getUTCDay();
    const offset = (8 - day) % 7;
    return addDays(date, offset);
  };

  const buildCandidateMondays = (termCode) => {
    const year = parseInt(String(termCode || '').slice(0, 4), 10);
    if (!year) return [];

    const start = mondayOnOrAfter(createUtcDate(year, 7, 1));
    const end = createUtcDate(year + 1, 8, 31);
    const todayTime = new Date().getTime();
    const dates = [];

    for (let date = start; date <= end; date = addDays(date, 7)) {
      dates.push(new Date(date.getTime()));
    }

    return dates.sort((a, b) =>
      Math.abs(a.getTime() - todayTime) - Math.abs(b.getTime() - todayTime)
    );
  };

  // dqzc.do 返回指定日期所在周次 ZC；用它反推第 1 周周一。
  const inferSemesterStartMonday = (termCode) => {
    const termParts = parseTermCode(termCode);
    if (!termParts) return null;

    const candidates = buildCandidateMondays(termCode);
    for (const date of candidates) {
      try {
        const data = syncRequest(CONFIG.CURRENT_WEEK_API, {
          XN: termParts.XN,
          XQ: termParts.XQ,
          RQ: formatDate(date),
        });
        const rows = extractRows(data, 'dqzc');
        const currentWeek = parseNumber(rows[0]?.ZC);
        if (currentWeek && currentWeek > 0 && currentWeek < 80) {
          return formatDate(addDays(date, (1 - currentWeek) * 7));
        }
      } catch (error) {
        continue;
      }
    }

    return null;
  };

  // 解析周次（优先使用bitmap，回退到文本解析）
  const parseWeeks = (zcmcText, bitMap) => {
    // 方案1：优先使用bitmap（最准确）
    if (typeof bitMap === 'string' && bitMap.length > 0) {
      const weeks = [];
      for (let i = 0; i < bitMap.length; i++) {
        if (bitMap[i] === '1') weeks.push(i + 1);
      }
      if (weeks.length > 0) return weeks;
    }

    // 方案2：解析文本（如"1-8周,9-16周(单)"）
    if (!zcmcText) return [];

    const weekSet = new Set();
    const parts = zcmcText.split(/[，,;；]/);

    parts.forEach(part => {
      const match = part.match(/(\d+)(?:-(\d+))?周?(?:\((单|双)\))?/);
      if (!match) return;

      const start = parseInt(match[1], 10);
      const end = match[2] ? parseInt(match[2], 10) : start;
      const parityFlags = { 单: 1, 双: 2 };
      const parity = parityFlags[match[3]] || 0;

      for (let w = start; w <= end; w++) {
        const isOdd = (w % 2 === 1);
        const shouldInclude =
          parity === 0 ||
          (parity === 1 && isOdd) ||
          (parity === 2 && !isOdd);

        if (shouldInclude) weekSet.add(w);
      }
    });

    return Array.from(weekSet).sort((a, b) => a - b);
  };

  // 转换单条课程数据为目标格式
  const transformCourse = (raw) => {
    const weeks = parseWeeks(raw.ZCMC, raw.SKZC);
    if (weeks.length === 0) return null;

    const weekTime = parseInt(raw.SKXQ, 10);
    const startTime = parseInt(raw.KSJC, 10);
    const endTime = parseInt(raw.JSJC, 10);
    if (!weekTime || !startTime || !endTime || endTime < startTime) return null;

    return {
      name: raw.KCM,
      classroom: raw.JASMC || raw.JASMC_DISPLAY || '',
      class_number: raw.KCH,
      teacher: raw.SKJS,
      test_time: null,
      test_location: null,
      link: null,
      weeks: weeks,
      week_time: weekTime,
      start_time: startTime,
      time_count: endTime - startTime, // 不 +1
      import_type: 1,
      info: raw.ZCMC,
      data: null,
    };
  };

  // 主流程
  try {
    // 步骤1：获取页面当前选择的学期
    const currentTerm = fetchTerm();

    if (!currentTerm?.DM) {
      throw new Error('无法获取当前学期信息');
    }

    console.log(`已选择学期：${currentTerm.DM} ${currentTerm.MC}`);

    // 步骤2：获取并转换课表数据
    const rawCourses = fetchSchedule(currentTerm.DM);
    const courses = rawCourses
      .map(transformCourse)
      .filter(course => course !== null); // 过滤无有效周次的课程

    const semesterStartMonday = inferSemesterStartMonday(currentTerm.DM);

    // 步骤3：组装并返回结果
    const result = {
      name: currentTerm.MC,
      courses: courses,
    };

    if (semesterStartMonday) {
      result.semester_start_monday = semesterStartMonday;
    }

    return encodeURIComponent(JSON.stringify(result));

  } catch (error) {
    console.error('课表解析失败:', error);
    return encodeURIComponent(
      JSON.stringify({
        name: '无法获取学期信息',
        courses: [],
      })
    );
  }
}

scheduleHtmlParser();
