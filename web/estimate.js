'use strict';

// Shared between the VM and Disks pages (loaded on both) so a VM picked on one and a disk
// picked on the other combine into one running estimate. Persisted via store.js under its own
// key - deliberately separate from ec2_settings/disk_settings, which are page-specific filter
// state, not meant to be shared across pages.
var Estimate = (function () {
  var STORAGE_KEY = 'azvms_estimate';
  var HOURS_PER_MONTH = 365 * 24 / 12; // same approximation the VM pricing script itself uses

  function get() {
    return store.get(STORAGE_KEY) || { vm: null, disk: null };
  }

  function save(state) {
    store.set(STORAGE_KEY, state);
    render();
  }

  function setVm(vm) {
    var state = get();
    state.vm = vm;
    save(state);
  }

  function setDisk(disk) {
    var state = get();
    state.disk = disk;
    save(state);
  }

  function clearVm() {
    var state = get();
    state.vm = null;
    save(state);
  }

  function clearDisk() {
    var state = get();
    state.disk = null;
    save(state);
  }

  function clearAll() {
    save({ vm: null, disk: null });
  }

  function render() {
    var $bar = $('#estimate-bar');
    if (!$bar.length) {
      return;
    }

    var state = get();
    if (!state.vm && !state.disk) {
      $bar.hide();
      return;
    }

    var onVmPage = location.pathname === '/' || location.pathname === '/index.html';
    var onDisksPage = location.pathname.indexOf('/disks') === 0;
    var vmMonthly = state.vm ? state.vm.cost * HOURS_PER_MONTH : 0;
    var diskMonthly = state.disk ? state.disk.cost : 0;
    var total = vmMonthly + diskMonthly;

    var parts = [];
    if (state.vm) {
      parts.push(
        '<span class="estimate-part">VM: <strong>' + state.vm.name + '</strong> ($'
        + state.vm.cost.toFixed(4) + '/hr, ' + state.vm.region + ')'
        + ' <a href="javascript:;" class="estimate-remove" data-target="vm" title="Remove">&times;</a></span>'
      );
    } else {
      parts.push(
        '<span class="estimate-part estimate-empty">No VM selected'
        + (onVmPage ? '' : ' - pick one on the <a href="/">Azure VM</a> tab') + '</span>'
      );
    }
    if (state.disk) {
      parts.push(
        '<span class="estimate-part">Disk: <strong>' + state.disk.name + '</strong> ($'
        + state.disk.cost.toFixed(2) + '/mo, ' + state.disk.region + ')'
        + ' <a href="javascript:;" class="estimate-remove" data-target="disk" title="Remove">&times;</a></span>'
      );
    } else {
      parts.push(
        '<span class="estimate-part estimate-empty">No disk selected'
        + (onDisksPage ? '' : ' - pick one on the <a href="/disks/">Disks</a> tab') + '</span>'
      );
    }

    var totalHtml = (state.vm && state.disk)
      ? '<span class="estimate-total">&asymp; $' + total.toFixed(2) + '/month combined</span>'
      : '<span class="estimate-total estimate-total-partial">$' + total.toFixed(2) + '/month so far</span>';

    $bar.html(
      parts.join(' + ') + ' ' + totalHtml
      + ' <button type="button" class="btn btn-xs btn-default estimate-clear">Clear estimate</button>'
    ).show();
  }

  $(document).on('click', '.estimate-remove', function () {
    if ($(this).data('target') === 'vm') {
      clearVm();
    } else {
      clearDisk();
    }
  });

  $(document).on('click', '.estimate-clear', function () {
    clearAll();
  });

  return {
    get: get,
    setVm: setVm,
    setDisk: setDisk,
    clearVm: clearVm,
    clearDisk: clearDisk,
    clearAll: clearAll,
    render: render
  };
})();

$(document).ready(function () {
  Estimate.render();
});
