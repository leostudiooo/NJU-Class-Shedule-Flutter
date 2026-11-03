const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const scriptPath = path.join(__dirname, '../../api/tools/seubksjw_terms.js');
const script = fs.readFileSync(scriptPath, 'utf8');
const courseParserPath = path.join(__dirname, '../../api/tools/seubksjw.js');
const courseParser = fs.readFileSync(courseParserPath, 'utf8');

test('returns the common manual-term contract with selected semester dates', () => {
  const calls = [];
  const responses = {
    '/modules/jshkcb/dqxnxq.do': {
      datas: {
        dqxnxq: {
          rows: [{ DM: '2025-2026-1', MC: '2025-2026学年第一学期' }],
        },
      },
    },
    '/modules/jshkcb/xnxqcx.do': {
      datas: {
        xnxqcx: {
          rows: [
            { DM: '2025-2026-1', MC: '2025-2026学年第一学期' },
            { DM: '2024-2025-2', MC: '2024-2025学年第二学期' },
          ],
        },
      },
    },
    '/modules/xskcb/cxxljc.do': {
      datas: {
        cxxljc: {
          rows: [{ XQKSRQ: '2025-09-01 00:00:00', ZZC: 20, ZJXZC: 18 }],
        },
      },
    },
  };

  const context = {
    window: {},
    WIS_EMAP_SERV: {
      getAbsPath: path => `https://ehall.seu.edu.cn/jwapp/sys/bykb${path}`,
    },
    BH_UTILS: {
      doSyncAjax: (url, params) => {
        const requestPath = new URL(url).pathname.replace('/jwapp/sys/bykb', '');
        calls.push({ requestPath, params });
        return responses[requestPath];
      },
    },
  };

  const encoded = vm.runInNewContext(script, context);
  const terms = JSON.parse(decodeURIComponent(encoded));

  assert.equal(terms.length, 2);
  assert.deepEqual(terms[0], {
    dm: '2025-2026-1',
    name: '2025-2026学年第一学期',
    xn: '2025-2026',
    xq: '1',
    start: '2025-09-01',
    weeks: 20,
    teachingWeeks: 18,
    selected: true,
  });
  assert.equal(terms[1].selected, false);
  assert.ok(calls.some(call => call.requestPath === '/modules/jshkcb/xnxqcx.do'));
  assert.ok(calls.some(call => call.requestPath === '/modules/xskcb/cxxljc.do'));
});

test('uses the selected manual term when requesting the course schedule', () => {
  const selectedTerm = {
    dm: '2024-2025-2',
    name: '2024-2025学年第二学期',
    semester_start_monday: '2025-02-17',
  };
  const calls = [];
  const responses = {
    '/modules/jshkcb/xnxqcx.do': {
      datas: {
        xnxqcx: {
          rows: [
            { DM: '2025-2026-1', MC: '2025-2026学年第一学期' },
            { DM: selectedTerm.dm, MC: selectedTerm.name },
          ],
        },
      },
    },
    '/modules/xskcb/cxxszhxqkb.do': {
      datas: {
        cxxszhxqkb: {
          rows: [{
            KCM: '数据库原理',
            JASMC: '教室 101',
            KCH: 'CS101',
            SKJS: '教师',
            SKZC: '1111',
            ZCMC: '1-4周',
            SKXQ: '2',
            KSJC: '3',
            JSJC: '5',
          }],
        },
      },
    },
  };
  const context = {
    window: { __course_import_selected_term__: selectedTerm },
    WIS_EMAP_SERV: {
      getAbsPath: path => `https://ehall.seu.edu.cn/jwapp/sys/bykb${path}`,
    },
    BH_UTILS: {
      doSyncAjax: (url, params) => {
        const requestPath = new URL(url).pathname.replace('/jwapp/sys/bykb', '');
        calls.push({ requestPath, params });
        return responses[requestPath];
      },
    },
  };

  const encoded = vm.runInNewContext(courseParser, context);
  const courseTable = JSON.parse(decodeURIComponent(encoded));
  const scheduleCall = calls.find(
    call => call.requestPath === '/modules/xskcb/cxxszhxqkb.do'
  );

  assert.equal(scheduleCall.params.XNXQDM, selectedTerm.dm);
  assert.equal(courseTable.name, selectedTerm.name);
  assert.equal(courseTable.semester_start_monday, selectedTerm.semester_start_monday);
  assert.equal(courseTable.courses.length, 1);
  assert.equal(courseTable.courses[0].name, '数据库原理');
  assert.equal(courseTable.courses[0].time_count, 2);
});
