'use strict';

var disks_data = [];
var loaded_disks = {};
var g_app_initialized = false;
var g_data_table = null;
var g_settings = {};

var g_settings_defaults = {
  region: 'uksouth',
  min_size: 0,
  max_size: 999999,
  min_iops: 0,
  min_throughput: 0,
  filter: '',
};

var TIER_LABELS = {
  Premium: 'Premium SSD',
  Standard: 'Standard HDD',
  StandardSSD: 'Standard SSD',
  PremiumV2: 'Premium SSD v2',
  UltraSSD: 'Ultra Disk',
};

function getParam(obj, key) {
  if (!obj || typeof obj[key] === 'undefined') {
    return null;
  }
  return obj[key];
}

$(document).on('click', '.btn-add-estimate[data-disk-key]', function () {
  var $btn = $(this);
  Estimate.setDisk({
    key: $btn.data('diskKey'),
    name: $btn.data('diskName'),
    cost: Number($btn.data('diskCost')),
    region: $btn.data('diskRegion')
  });
});

// Finds the Consumption-type price row for a region whose meterName contains `meterKeyword`
// (or, for fixed-tier disks with a single meter, any keyword).
function findRawPrice(prices, region, meterKeyword) {
  if (!prices || !prices.length) {
    return null;
  }
  var match = prices.find(function (p) {
    return p.armRegionName === region
      && p.type === 'Consumption'
      && (!meterKeyword || (p.meterName || '').indexOf(meterKeyword) !== -1);
  });
  return match || null;
}

function findPrice(prices, region, meterKeyword) {
  var match = findRawPrice(prices, region, meterKeyword);
  if (!match) {
    return '';
  }
  return '$' + Number(match.retailPrice).toFixed(4) + ' / ' + match.unitOfMeasure;
}

function escape_attr(str) {
  return String(str).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
}

function generate_data_table(region) {
  var res = loaded_disks;
  disks_data.length = 0;

  for (var key in res) {
    var entry = res[key];
    var specs = getParam(entry, 'specs') || {};
    var prices = getParam(entry, 'prices') || [];

    var min_size = getParam(g_settings, 'min_size');
    var max_size = getParam(g_settings, 'max_size');
    var min_iops = getParam(g_settings, 'min_iops');
    var min_throughput = getParam(g_settings, 'min_throughput');

    var maxSizeGiB = Number(getParam(specs, 'MaxSizeGiB')) || 0;
    var minSizeGiB = Number(getParam(specs, 'MinSizeGiB')) || 0;
    var maxIops = Number(getParam(specs, 'MaxIOps') !== null ? getParam(specs, 'MaxIOps') : getParam(specs, 'MaxIOpsReadWrite')) || 0;
    var maxThroughput = Number(getParam(specs, 'MaxBandwidthMBps') !== null ? getParam(specs, 'MaxBandwidthMBps') : getParam(specs, 'MaxBandwidthMBpsReadWrite')) || 0;
    var maxBurstIops = Number(getParam(specs, 'MaxBurstIops')) || 0;
    var maxBurstThroughput = Number(getParam(specs, 'MaxBurstBandwidthMBps')) || 0;
    var maxShares = Number(getParam(specs, 'MaxValueOfMaxShares')) || 0;

    if (maxSizeGiB < min_size || (max_size > 0 && minSizeGiB > max_size)) {
      continue;
    }
    if (maxIops < min_iops || maxThroughput < min_throughput) {
      continue;
    }

    var tier = getParam(specs, 'tier');
    var isFixedTier = tier === 'Premium' || tier === 'Standard' || tier === 'StandardSSD';

    var row = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var displayName = (getParam(specs, 'name') || '') + ' ' + (getParam(specs, 'redundancy') || '');
    row[0] = displayName;
    row[1] = TIER_LABELS[tier] || tier || '';
    row[2] = getParam(specs, 'redundancy') || '';
    row[3] = minSizeGiB || '';
    row[4] = maxSizeGiB || '';
    row[5] = maxIops || '';
    row[6] = maxThroughput || '';
    row[7] = maxBurstIops || '';
    row[8] = maxBurstThroughput || '';
    row[9] = maxShares || '';
    row[10] = isFixedTier ? findPrice(prices, region, null) : '';
    row[11] = isFixedTier ? '' : findPrice(prices, region, 'Capacity');
    row[12] = isFixedTier ? '' : findPrice(prices, region, 'IOPS');
    row[13] = isFixedTier ? '' : findPrice(prices, region, 'Throughput');

    // Only fixed-tier disks have a single flat monthly price - PremiumV2/UltraSSD are billed per
    // provisioned GiB/IOPS/MBps, which this UI has no capacity input to compute a real number
    // from, so leave them out of the estimate rather than showing a misleading total.
    var rawPrice = isFixedTier ? findRawPrice(prices, region, null) : null;
    if (rawPrice) {
      row[14] = '<button type="button" class="btn btn-xs btn-primary btn-add-estimate" '
        + 'data-disk-key="' + escape_attr(key) + '" '
        + 'data-disk-name="' + escape_attr(displayName) + '" '
        + 'data-disk-cost="' + Number(rawPrice.retailPrice) + '" '
        + 'data-disk-region="' + escape_attr(region) + '">Add to estimate</button>';
    } else {
      row[14] = '<button type="button" class="btn btn-xs" disabled title="Only available for fixed-price disks (Premium/Standard/StandardSSD)">Unavailable</button>';
    }

    disks_data.push(row);
  }
}

function init_data_table() {
  $("#data thead tr").clone(true).appendTo("#data thead");
  $("#data thead tr:eq(1) th").each(function (i) {
    var title = $(this).text();
    $(this).html("<input type='text' placeholder='Search '" + title + "' />");
    $("input", this).on("keyup change", function () {
      if (g_data_table.column(i).search() !== this.value) {
        g_data_table.column(i).search(this.value).draw();
      }
    });
  });

  // Keyed on column count so a future column change can't collide with a visitor's stale saved
  // state - see the same pattern in ../default.js for why.
  var stateStorageKey = 'DataTables_disks_cols' + $('#data thead tr:eq(0) th').length;

  g_data_table = $('#data').DataTable({
    "data": disks_data,
    "bPaginate": false,
    "bInfo": false,
    "bStateSave": true,
    "stateSaveCallback": function (settings, data) {
      localStorage.setItem(stateStorageKey, JSON.stringify(data));
    },
    "stateLoadCallback": function (settings) {
      var saved = localStorage.getItem(stateStorageKey);
      return saved ? JSON.parse(saved) : null;
    },
    "orderCellsTop": true,
    "oSearch": {
      "bRegex": true,
      "bSmart": false
    },
    "aoColumnDefs": [
      {
        "aTargets": [
          "minsize", "maxsize", "maxiops", "maxthroughput",
          "maxburstiops", "maxburstthroughput", "maxshares",
          "price-fixed", "price-capacity", "price-iops", "price-throughput"
        ],
        "sType": "cust-sort"
      },
      {
        "aTargets": ["maxburstiops", "maxburstthroughput", "maxshares"],
        "bVisible": false
      }
    ],
    "aaSorting": [
      [0, "asc"]
    ],
    'initComplete': function () {
      setTimeout(function () {
        on_data_table_initialized();
      }, 0);
    },
    'stateSave': true,
    'buttons': ['csv']
  });

  g_data_table
    .buttons()
    .container()
    .find('a')
    .addClass('btn btn-primary')
    .appendTo($('#menu > div'));

  return g_data_table;
}

function change_region(region) {
  g_settings.region = region;
  var region_name = null;
  $('#region-dropdown li a').each(function (i, e) {
    e = $(e);
    if (e.data('region') === region) {
      e.parent().addClass('active');
      region_name = e.text();
    } else {
      e.parent().removeClass('active');
    }
  });
  $("#region-dropdown .dropdown-toggle .text").text(region_name);

  generate_data_table(region);
  g_data_table.clear();
  g_data_table.rows.add(disks_data);
  g_data_table.draw();
}

function setup_column_toggle() {
  $.each(g_data_table.columns().indexes(), function (i, idx) {
    var column = g_data_table.column(idx);
    $("#filter-dropdown ul").append(
      $('<li>')
        .toggleClass('active', column.visible())
        .append(
          $('<a>', { href: "javascript:;" })
            .text($(column.header()).text())
            .click(function (e) {
              column.visible(!column.visible());
              $(this).parent().toggleClass("active");
              $(this).blur();
              e.stopPropagation();
            })
        )
    );
  });
}

function setup_clear() {
  $('.btn-clear').click(function () {
    g_settings = JSON.parse(JSON.stringify(g_settings_defaults));
    g_data_table.search("");
    maybe_update_url();
    store.set('disk_settings', undefined);
    g_data_table.state.clear();
    window.location.reload();
  });
}

function apply_minmax_values() {
  var all_filters = $('[data-action="datafilter"]');

  all_filters.each(function () {
    var filter_on = $(this).data('type').split('-');
    var filter_val = parseFloat($(this).val()) || 0;

    if (filter_on[0] == 'min') {
      g_settings["min_" + filter_on[1]] = filter_val;
    } else if (filter_on[0] == 'max') {
      g_settings["max_" + filter_on[1]] = filter_val;
    }
  });
  maybe_update_url();
  change_region(g_settings.region);
}

function maybe_update_url() {
  store.set('disk_settings', g_settings);

  if (!history.replaceState) {
    return;
  }

  try {
    var params = {};
    for (var key in g_settings) {
      if (g_settings[key] !== '' && g_settings[key] != null && g_settings[key] !== g_settings_defaults[key]) {
        params[key] = g_settings[key];
      }
    }

    var url = location.origin + location.pathname;
    var parameters = [];
    for (var setting in params) {
      // Encode both sides - a search term with &, =, %, #, or spaces would otherwise silently
      // break the query string (and any such characters wouldn't round-trip on load at all).
      parameters.push(encodeURIComponent(setting) + '=' + encodeURIComponent(String(params[setting])));
    }
    if (parameters.length > 0) {
      url = url + '?' + parameters.join('&');
    }

    if (document.location == url) {
      return;
    }

    history.replaceState(null, '', url);
  } catch (ex) {
    // doesn't matter
  }
}

function load_settings() {
  g_settings = store.get('disk_settings') || {};

  if (location.search) {
    var params = location.search.slice(1).split('&');
    params.forEach(function (param) {
      // Split on the first '=' only (a decoded value could itself contain one) and decode both
      // sides to match how maybe_update_url() encodes them.
      var eq = param.indexOf('=');
      var key = decodeURIComponent(eq === -1 ? param : param.slice(0, eq));
      var val = eq === -1 ? '' : decodeURIComponent(param.slice(eq + 1));
      g_settings[key] = val;
    });
  }

  for (var key in g_settings_defaults) {
    if (g_settings[key] === undefined) {
      g_settings[key] = g_settings_defaults[key];
    }
  }

  return g_settings;
}

function on_data_table_initialized() {
  if (g_app_initialized) return;
  g_app_initialized = true;

  load_settings();

  $('[data-action="datafilter"][data-type="min-size"]').val(g_settings['min_size']);
  $('[data-action="datafilter"][data-type="max-size"]').val(g_settings['max_size']);
  $('[data-action="datafilter"][data-type="min-iops"]').val(g_settings['min_iops']);
  $('[data-action="datafilter"][data-type="min-throughput"]').val(g_settings['min_throughput']);
  g_data_table.search(g_settings['filter']);
  apply_minmax_values();

  $.extend($.fn.dataTableExt.oStdClasses, {
    "sWrapper": "dataTables_wrapper form-inline"
  });

  setup_column_toggle();
  setup_clear();

  $('[data-action=datafilter]').on('keyup', apply_minmax_values);

  $("#region-dropdown li").bind("click", function (e) {
    change_region($(e.target).data('region'));
  });

  $('div.dataTables_filter input').addClass('form-control search');
}

jQuery.extend(jQuery.fn.dataTableExt.oSort, {
  "cust-sort-pre": function (elem) {
    if (!elem) {
      return -1e6;
    }
    var parts = elem.split(" ");
    var res = parts[0].replace('$', '');
    return isNaN(Number(res)) ? -1e5 : Number(res);
  },

  "cust-sort-asc": function (a, b) {
    return ((a < b) ? -1 : ((a > b) ? 1 : 0));
  },

  "cust-sort-desc": function (a, b) {
    return ((a < b) ? 1 : ((a > b) ? -1 : 0));
  },
});

async function loadLastUpdateTime() {
  try {
    const response = await fetch('../lastupdate.json', { cache: 'no-store' });
    const config = await response.json();

    const lastUpdateTime = config.lastUpdateTime;

    document.getElementById('lastUpdateTimeHeader').textContent = lastUpdateTime;
    document.getElementById('lastUpdateTimeFooter').textContent = lastUpdateTime;
  }
  catch (error) {
    console.error("Failed to replace last update time:", error)
  }
}

$(document).ready(function () {
  loadLastUpdateTime()
  $.ajax({
    url: "../disks.json",
    cache: false,
  }).done(function (res) {
    loaded_disks = res;

    var allRegions = [];
    for (var key in res) {
      var prices = getParam(res[key], 'prices') || [];
      prices.forEach(function (p) {
        if (p.armRegionName && allRegions.indexOf(p.armRegionName) === -1) {
          allRegions.push(p.armRegionName);
        }
      });
    }
    allRegions.sort();

    allRegions.forEach(function (val) {
      $('#region-menu').append('<li><a href="javascript:;" data-region="' + val + '">' + val + '</a></li>');
    });

    load_settings();
    generate_data_table(g_settings.region);
    init_data_table();
  });
});
