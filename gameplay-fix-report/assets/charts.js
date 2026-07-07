// Goal completion chart for all 46 levels
// Reads CSS variables from the report theme
(function() {
  var style = getComputedStyle(document.documentElement);
  var accent = style.getPropertyValue('--accent').trim() || '#58a6ff';
  var accent2 = style.getPropertyValue('--accent2').trim() || '#f78166';
  var ink = style.getPropertyValue('--ink').trim() || '#e6edf3';
  var muted = style.getPropertyValue('--muted').trim() || '#8b949e';
  var rule = style.getPropertyValue('--rule').trim() || '#30363d';
  var bg2 = style.getPropertyValue('--bg2').trim() || '#161b22';
  var green = style.getPropertyValue('--green').trim() || '#3fb950';
  var red = style.getPropertyValue('--red').trim() || '#f85149';
  var yellow = style.getPropertyValue('--yellow').trim() || '#d29922';

  // Level data: [label, goalsDone, goalsTotal, atoms, bonds]
  // v17: all 46 levels COMPLETED after charge_balance deletion guard + direct bond registration fix
  var levelData = [
    ["C1-L1", 2, 2, 7, 0],
    ["C1-L2", 6, 6, 26, 148],
    ["C1-L3", 5, 5, 8, 21],
    ["C1-L4", 6, 6, 10, 35],
    ["C1-L5", 5, 5, 10, 41],
    ["C1-L6", 4, 4, 18, 96],
    ["C1-L7", 7, 7, 18, 50],
    ["C2-L1", 7, 7, 26, 146],
    ["C2-L2", 7, 7, 8, 37],
    ["C2-L3", 7, 7, 8, 37],
    ["C2-L4", 5, 5, 4, 4],
    ["C2-L5", 4, 4, 10, 35],
    ["C2-L6", 4, 4, 20, 95],
    ["C2-L7", 4, 4, 7, 25],
    ["C3-L1", 6, 6, 8, 24],
    ["C3-L2", 9, 9, 20, 60],
    ["C3-L3", 6, 6, 24, 67],
    ["C3-L4", 5, 5, 8, 26],
    ["C3-L5", 6, 6, 5, 9],
    ["C3-L6", 5, 5, 6, 12],
    ["C3-L7", 8, 8, 6, 14],
    ["C3-L8", 5, 5, 30, 20],
    ["C3-L9", 5, 5, 30, 130],
    ["C3-L10", 6, 6, 30, 20],
    ["C3-L11", 6, 6, 50, 210],
    ["C4-L1", 5, 5, 12, 52],
    ["C4-L2", 8, 8, 16, 55],
    ["C4-L3", 6, 6, 7, 21],
    ["C4-L4", 10, 10, 14, 76],
    ["C4-L5", 7, 7, 3, 3],
    ["C4-L6", 6, 6, 30, 118],
    ["C4-L7", 5, 5, 17, 78],
    ["C4-L8", 7, 7, 14, 49],
    ["C4-L9", 5, 5, 30, 108],
    ["C5-L1", 6, 6, 30, 118],
    ["C5-L2", 3, 3, 0, 0],
    ["C5-L3", 4, 4, 0, 0],
    ["C5-L4", 6, 6, 8, 36],
    ["C5-L5", 6, 6, 2, 1],
    ["C5-L6", 6, 6, 0, 0],
    ["C5-L7", 5, 5, 8, 21],
    ["C5-L8", 4, 4, 50, 291],
    ["C0-L1", 5, 5, 31, 85],
    ["C-1-L1", 4, 4, 10, 36],
    ["C-1-L2", 6, 6, 11, 33],
    ["C-1-L3", 5, 5, 8, 36]
  ];

  var labels = levelData.map(function(d) { return d[0]; });
  var goalsDone = levelData.map(function(d) { return d[1]; });
  var goalsTotal = levelData.map(function(d) { return d[2]; });
  var atoms = levelData.map(function(d) { return d[3]; });
  var bonds = levelData.map(function(d) { return d[4]; });

  // Color bars based on completion ratio
  var barColors = levelData.map(function(d) {
    var ratio = d[2] > 0 ? d[1] / d[2] : 0;
    if (ratio >= 1.0) return green;
    if (ratio > 0) return yellow;
    return red;
  });

  var chart1 = echarts.init(document.getElementById('chart-goals'), null, { renderer: 'svg' });
  chart1.setOption({
    animation: false,
    backgroundColor: 'transparent',
    title: {
      text: '目标完成数 / 总目标数',
      left: 'center',
      textStyle: { color: ink, fontSize: 14, fontWeight: 600 }
    },
    tooltip: {
      trigger: 'item',
      appendToBody: true,
      formatter: function(params) {
        var idx = params.dataIndex;
        var d = levelData[idx];
        var ratio = d[2] > 0 ? Math.round(d[1] / d[2] * 100) : 0;
        return '<b>' + d[0] + '</b><br/>'
          + '目标完成: ' + d[1] + '/' + d[2] + ' (' + ratio + '%)<br/>'
          + '原子数: ' + d[3] + '<br/>'
          + '键数: ' + d[4];
      },
      backgroundColor: bg2,
      borderColor: rule,
      textStyle: { color: ink }
    },
    legend: {
      data: ['已完成目标', '总目标数'],
      top: 30,
      textStyle: { color: muted }
    },
    grid: {
      left: '3%',
      right: '3%',
      bottom: '8%',
      top: 70,
      containLabel: true
    },
    xAxis: {
      type: 'category',
      data: labels,
      axisLabel: {
        color: muted,
        fontSize: 10,
        rotate: 45,
        interval: 0
      },
      axisLine: { lineStyle: { color: rule } }
    },
    yAxis: {
      type: 'value',
      name: '目标数',
      nameTextStyle: { color: muted },
      axisLabel: { color: muted },
      splitLine: { lineStyle: { color: rule, type: 'dashed' } }
    },
    series: [
      {
        name: '已完成目标',
        type: 'bar',
        data: goalsDone.map(function(v, i) {
          return { value: v, itemStyle: { color: barColors[i] } };
        }),
        barGap: '10%',
        z: 2
      },
      {
        name: '总目标数',
        type: 'bar',
        data: goalsTotal,
        itemStyle: { color: rule, opacity: 0.5 },
        z: 1
      }
    ]
  });
  window.addEventListener('resize', function() { chart1.resize(); });

  // --- Chart 2: Atoms & Bonds per level ---
  var chart2Container = document.getElementById('chart-atoms');
  if (chart2Container) {
    var chart2 = echarts.init(chart2Container, null, { renderer: 'svg' });
    chart2.setOption({
      animation: false,
      backgroundColor: 'transparent',
      title: {
        text: '原子与键的数量',
        left: 'center',
        textStyle: { color: ink, fontSize: 14, fontWeight: 600 }
      },
      tooltip: {
        trigger: 'axis',
        appendToBody: true,
        backgroundColor: bg2,
        borderColor: rule,
        textStyle: { color: ink }
      },
      legend: {
        data: ['原子数', '键数'],
        top: 30,
        textStyle: { color: muted }
      },
      grid: {
        left: '3%',
        right: '3%',
        bottom: '8%',
        top: 70,
        containLabel: true
      },
      xAxis: {
        type: 'category',
        data: labels,
        axisLabel: {
          color: muted,
          fontSize: 10,
          rotate: 45,
          interval: 0
        },
        axisLine: { lineStyle: { color: rule } }
      },
      yAxis: {
        type: 'value',
        axisLabel: { color: muted },
        splitLine: { lineStyle: { color: rule, type: 'dashed' } }
      },
      series: [
        {
          name: '原子数',
          type: 'bar',
          data: atoms,
          itemStyle: { color: accent }
        },
        {
          name: '键数',
          type: 'bar',
          data: bonds,
          itemStyle: { color: accent2 }
        }
      ]
    });
    window.addEventListener('resize', function() { chart2.resize(); });
  }

  // --- Chart 3: Status distribution pie ---
  var chart3Container = document.getElementById('chart-status');
  if (chart3Container) {
    var completed = levelData.filter(function(d) { return d[1] > 0 && d[1] === d[2]; }).length;
    var explored = levelData.filter(function(d) { return d[3] === 0 && !(d[1] > 0 && d[1] === d[2]); }).length;
    var partial = levelData.length - completed - explored;

    var chart3 = echarts.init(chart3Container, null, { renderer: 'svg' });
    chart3.setOption({
      animation: false,
      backgroundColor: 'transparent',
      title: {
        text: '关卡状态分布',
        left: 'center',
        textStyle: { color: ink, fontSize: 14, fontWeight: 600 }
      },
      tooltip: {
        trigger: 'item',
        appendToBody: true,
        formatter: '{b}: {c} 关 ({d}%)',
        backgroundColor: bg2,
        borderColor: rule,
        textStyle: { color: ink }
      },
      series: [{
        type: 'pie',
        radius: ['40%', '70%'],
        center: ['50%', '55%'],
        label: {
          color: ink,
          fontSize: 12,
          formatter: '{b}\n{c} 关'
        },
        data: [
          { value: completed, name: 'COMPLETED', itemStyle: { color: green } },
          { value: partial, name: 'PARTIAL (有进展)', itemStyle: { color: yellow } },
          { value: explored, name: 'EXPLORED (0原子)', itemStyle: { color: red } }
        ]
      }]
    });
    window.addEventListener('resize', function() { chart3.resize(); });
  }
})();
