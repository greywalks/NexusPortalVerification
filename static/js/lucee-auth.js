// Runtime authorization chrome for the Lucee port. Server-side authorization
// remains authoritative; this only mirrors permissions in the navigation.
(function () {
  const auth = window.LOGICORE_AUTH || {};
  const sections = new Set(auth.sections || []);
  const children = new Set(auth.invoiceChildren || []);
  const superadmin = !!auth.isSuperadmin;

  function hide(id) {
    const el = document.getElementById(id);
    if (el) el.classList.add('hidden');
  }

  function wireInventoryNav() {
    const inventory = document.getElementById('portal-nav-tbd2');
    if (!inventory) return;
    inventory.removeAttribute('data-portal');
    inventory.removeAttribute('onclick');
    inventory.id = 'portal-nav-inventory-management';
    const label = inventory.querySelector('span');
    if (label) label.textContent = 'Inventory Management';
    inventory.addEventListener('click', function (event) {
      event.preventDefault();
      window.location.href = '/index.cfm/inventory-management/';
    });
  }

  function enforceNav() {
    const adminNav = document.getElementById('portal-nav-admin-permissions');
    if (superadmin && adminNav) adminNav.classList.remove('hidden');
    if (!superadmin) {
      if (!sections.has('invoice-generator')) {
        hide('portal-nav-invoice-generator');
        hide('portal-body-invoice-generator');
        hide('portal-content-invoice-generator');
      } else {
        ['promethean','amc','tcl','philips','config'].forEach(client => {
          if (!children.has(client)) {
            hide('nav-' + client);
            hide('page-' + client);
            if (client === 'config') hide('portal-system-config');
          }
        });
      }
      if (!sections.has('sms-nonconforming')) {
        hide('portal-nav-sms-nonconforming');
        hide('portal-content-sms-nonconforming');
      }
      if (!sections.has('training-tracker')) hide('portal-nav-training-tracker');
      if (!sections.has('tbd2')) {
        hide('portal-nav-inventory-management');
        hide('portal-content-tbd2');
      }
      hide('portal-nav-admin-permissions');
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { wireInventoryNav(); enforceNav(); });
  else { wireInventoryNav(); enforceNav(); }
})();
