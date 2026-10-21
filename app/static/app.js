/* =====================================================================
   KhoHàng – JavaScript giao diện (thuần, không thư viện ngoài)
   File tĩnh nạp bằng <script src> nên hợp lệ với CSP "script-src 'self'".
   Không dùng onclick/style nội tuyến; vị trí menu đặt qua CSSOM (được CSP cho phép).
   Trang vẫn dùng được khi tắt JavaScript: lọc/sắp xếp/phân trang chạy phía server.
   ===================================================================== */
(function () {
  "use strict";

  var $ = function (sel, root) { return (root || document).querySelector(sel); };
  var $$ = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };
  var nf = new Intl.NumberFormat("vi-VN");
  var money = function (v) { return nf.format(Math.round(v || 0)) + " ₫"; };
  // Bỏ dấu tiếng Việt để gõ "ban phim" vẫn tìm thấy "Bàn phím"
  var norm = function (s) {
    return (s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/đ/g, "d").replace(/Đ/g, "D").toLowerCase();
  };
  var fire = function (el, type) { el.dispatchEvent(new Event(type, { bubbles: true })); };

  /* ---------------------------------------------------------------- menu thao tác */
  function closeMenus(except) {
    $$("details.menu[open]").forEach(function (d) { if (d !== except) d.open = false; });
  }
  function placeMenu(d) {
    // Đặt menu theo toạ độ màn hình để không bị khung cuộn của bảng cắt mất
    var list = $(".menu-list", d), btn = $("summary", d);
    if (!list || !btn) return;
    list.classList.add("fixed");
    var r = btn.getBoundingClientRect(), w = list.offsetWidth, h = list.offsetHeight;
    var top = r.bottom + 6;
    if (top + h > window.innerHeight - 8) top = Math.max(8, r.top - h - 6);
    var left = Math.max(8, Math.min(r.right - w, window.innerWidth - w - 8));
    list.style.left = left + "px";
    list.style.top = top + "px";
  }
  document.addEventListener("toggle", function (e) {
    var d = e.target;
    if (d.matches && d.matches("details.menu") && d.open) { closeMenus(d); placeMenu(d); }
  }, true);
  document.addEventListener("click", function (e) { if (!e.target.closest("details.menu")) closeMenus(); });
  document.addEventListener("keydown", function (e) { if (e.key === "Escape") closeMenus(); });
  // Khi cuộn/đổi kích thước: đặt lại vị trí menu đang mở thay vì đóng nó
  var reposition = function () { $$("details.menu[open]").forEach(placeMenu); };
  window.addEventListener("resize", reposition);
  window.addEventListener("scroll", reposition, true);

  /* ---------------------------------------------------------------- hộp thoại xác nhận xoá */
  function initConfirm() {
    var dlg = $("#confirm-dialog"), pending = null;
    document.addEventListener("submit", function (e) {
      var form = e.target, msg = form.getAttribute("data-confirm");
      if (!msg || form.dataset.confirmed === "1") return;
      e.preventDefault();
      closeMenus();
      if (!dlg || typeof dlg.showModal !== "function") {
        if (window.confirm(msg)) { form.dataset.confirmed = "1"; form.submit(); }
        return;
      }
      pending = form;
      $("[data-confirm-text]", dlg).textContent = msg;
      dlg.showModal();
      $("[data-confirm-cancel]", dlg).focus();
    });
    if (!dlg) return;
    $("[data-confirm-cancel]", dlg).addEventListener("click", function () { dlg.close(); });
    $("[data-confirm-ok]", dlg).addEventListener("click", function () {
      if (pending) { pending.dataset.confirmed = "1"; pending.submit(); }
      dlg.close();
    });
    dlg.addEventListener("close", function () { pending = null; });
  }

  /* ---------------------------------------------------------------- tìm kiếm, lọc theo thời gian thực */
  function initLive() {
    var form = $("[data-live-form]"), results = $("[data-live-results]");
    if (!form || !results) return;
    $$("[data-js-hide]", form).forEach(function (b) { b.hidden = true; });
    var scope = form.closest(".card") || document.body, timer = null, ctrl = null;

    function formUrl() {
      var params = new URLSearchParams();
      new FormData(form).forEach(function (v, k) { if (String(v).trim() !== "") params.append(k, v); });
      var qs = params.toString();
      return form.getAttribute("action") + (qs ? "?" + qs : "");
    }
    function syncFromUrl(url) {
      var sp = new URL(url, location.href).searchParams;
      $$('input[type="hidden"]', form).forEach(function (i) { i.value = sp.get(i.name) || ""; });
      $$("[data-export-link]").forEach(function (a) {
        var u = new URL(a.href, location.href), p = new URLSearchParams(sp);
        p.delete("page");
        u.search = p.toString();
        a.href = u.toString();
      });
    }
    function load(url) {
      if (ctrl) ctrl.abort();
      ctrl = new AbortController();
      scope.classList.add("loading");
      fetch(url, { credentials: "same-origin", signal: ctrl.signal })
        .then(function (res) {
          if (new URL(res.url).pathname.indexOf("/login") === 0) { location.href = res.url; return null; }
          return res.text();
        })
        .then(function (html) {
          if (html === null) return;
          var fresh = new DOMParser().parseFromString(html, "text/html").querySelector("[data-live-results]");
          if (!fresh) { location.href = url; return; }
          results.innerHTML = fresh.innerHTML;
          syncFromUrl(url);
          history.replaceState(null, "", url);
        })
        .catch(function (err) { if (err.name !== "AbortError") location.href = url; })
        .then(function () { scope.classList.remove("loading"); });
    }
    form.addEventListener("input", function (e) {
      if (!e.target.matches("input[type=search], input[type=number]")) return;
      clearTimeout(timer);
      timer = setTimeout(function () { load(formUrl()); }, 300);
    });
    form.addEventListener("change", function (e) {
      if (e.target.matches("select, input[type=date]")) load(formUrl());
    });
    form.addEventListener("submit", function (e) { e.preventDefault(); load(formUrl()); });
    results.addEventListener("click", function (e) {
      var a = e.target.closest("a[data-live-link]");
      if (!a || e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
      e.preventDefault();
      if (a.hasAttribute("data-reset")) {
        $$("input, select", form).forEach(function (el) {
          if (el.type === "hidden") return;
          if (el.tagName === "SELECT") el.selectedIndex = 0; else el.value = "";
        });
      }
      load(a.href);
      if (a.closest(".pager")) scope.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  }

  /* ---------------------------------------------------------------- ô chọn có gợi ý (combobox) */
  var comboSeq = 0;
  function makeCombo(select) {
    var id = "combo-" + (++comboSeq);
    var required = select.required;
    var opts = Array.prototype.slice.call(select.options);
    var wrap = document.createElement("div");
    var input = document.createElement("input");
    var list = document.createElement("ul");
    var chev = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    var use = document.createElementNS("http://www.w3.org/2000/svg", "use");
    wrap.className = "combo";
    input.type = "text";
    input.autocomplete = "off";
    input.placeholder = select.dataset.placeholder || "";
    input.setAttribute("role", "combobox");
    input.setAttribute("aria-autocomplete", "list");
    input.setAttribute("aria-expanded", "false");
    input.setAttribute("aria-controls", id);
    input.required = required;
    list.className = "combo-list";
    list.id = id;
    list.setAttribute("role", "listbox");
    list.hidden = true;
    chev.setAttribute("class", "icon");
    chev.setAttribute("aria-hidden", "true");
    use.setAttribute("href", "#i-chevron-down");
    chev.appendChild(use);
    select.parentNode.insertBefore(wrap, select);
    wrap.appendChild(input);
    wrap.appendChild(chev);
    wrap.appendChild(list);
    wrap.appendChild(select);
    select.required = false;
    select.tabIndex = -1;
    select.classList.add("native-hidden");
    select.setAttribute("aria-hidden", "true");

    var shown = [], active = -1;
    var labelOf = function (o) { return o && o.value ? o.textContent.trim() : ""; };
    function sync() { input.value = labelOf(select.selectedOptions[0]); input.setCustomValidity(""); }
    function setActive(i) {
      active = i;
      $$("li", list).forEach(function (li, k) { li.setAttribute("aria-selected", k === i ? "true" : "false"); });
      if (i >= 0 && list.children[i]) {
        input.setAttribute("aria-activedescendant", list.children[i].id);
        list.children[i].scrollIntoView({ block: "nearest" });
      } else {
        input.removeAttribute("aria-activedescendant");
      }
    }
    function render(text) {
      var q = norm(text);
      shown = opts.filter(function (o) {
        if (!o.value) return !required && !q;
        return !q || norm(o.textContent + " " + (o.dataset.sku || "")).indexOf(q) !== -1;
      }).slice(0, 60);
      list.textContent = "";
      shown.forEach(function (o, i) {
        var li = document.createElement("li"), main = document.createElement("span");
        li.id = id + "-" + i;
        li.setAttribute("role", "option");
        main.textContent = o.textContent.trim();
        li.appendChild(main);
        if (o.dataset.meta) {
          var meta = document.createElement("small");
          meta.textContent = o.dataset.meta;
          li.appendChild(meta);
        }
        li.addEventListener("mousedown", function (ev) { ev.preventDefault(); choose(o); });
        list.appendChild(li);
      });
      if (!shown.length) {
        var none = document.createElement("li");
        none.className = "none";
        none.textContent = "Không tìm thấy kết quả phù hợp";
        list.appendChild(none);
      }
      setActive(shown.length ? 0 : -1);
    }
    function open(text) {
      render(text);
      list.hidden = false;
      input.setAttribute("aria-expanded", "true");
    }
    function close() {
      list.hidden = true;
      input.setAttribute("aria-expanded", "false");
    }
    function choose(o) {
      select.value = o.value;
      sync();
      close();
      fire(select, "change");
    }
    input.addEventListener("focus", function () { input.select(); open(""); });
    input.addEventListener("click", function () { if (list.hidden) open(""); });
    input.addEventListener("input", function () {
      input.setCustomValidity("");
      open(input.value);
      if (select.value && input.value !== labelOf(select.selectedOptions[0])) { select.value = ""; fire(select, "change"); }
    });
    input.addEventListener("keydown", function (e) {
      if (e.key === "ArrowDown") { e.preventDefault(); if (list.hidden) open(""); else setActive(Math.min(active + 1, shown.length - 1)); }
      else if (e.key === "ArrowUp") { e.preventDefault(); setActive(Math.max(active - 1, 0)); }
      else if (e.key === "Enter" && !list.hidden && shown[active]) { e.preventDefault(); choose(shown[active]); }
      else if (e.key === "Escape") { close(); sync(); }
    });
    input.addEventListener("blur", function () { close(); sync(); });
    if (required && select.form) {
      select.form.addEventListener("submit", function (e) {
        if (select.value) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        input.setCustomValidity("Chọn một mục trong danh sách gợi ý");
        input.reportValidity();
      }, true);
    }
    sync();
  }

  /* ---------------------------------------------------------------- xem trước sản phẩm trong phiếu */
  function initStockPreview() {
    var form = $("[data-stock-form]");
    if (!form) return;
    var sel = $("[data-stock-product]", form), qty = $("[data-stock-qty]", form), price = $("[data-stock-price]", form);
    var isIn = form.dataset.direction === "in", pv = $("[data-pv]"), empty = $("[data-pv-empty]");
    var set = function (key, text) { var el = $("[data-pv-" + key + "]"); if (el) el.textContent = text; };
    function update() {
      var o = sel.selectedOptions[0], unitLabel = $("[data-unit-label]");
      if (!o || !o.value) { pv.hidden = true; empty.hidden = false; unitLabel.textContent = "đơn vị"; return; }
      var d = o.dataset, cur = +d.qty, min = +d.min, p = +d.price, q = Math.max(+qty.value || 0, 0);
      var unitPrice = price.value !== "" ? +price.value : p, after = isIn ? cur + q : cur - q;
      var thumb = $("[data-pv-thumb]");
      pv.hidden = false;
      empty.hidden = true;
      thumb.textContent = d.initials;
      thumb.className = "thumb tone-c" + d.tone;
      unitLabel.textContent = d.unit;
      set("name", d.name);
      set("sku", d.sku + (d.category ? ", " + d.category : ""));
      set("price", money(p));
      set("qty", nf.format(cur) + " " + d.unit);
      set("min", nf.format(min) + " " + d.unit);
      set("supplier", d.supplier || "Chưa gán");
      set("after-qty", nf.format(after) + " " + d.unit);
      set("amount", money(q * unitPrice));
      var over = !isIn && q > cur, warn = $("[data-pv-warn]");
      $("[data-pv-after]").classList.toggle("bad", over);
      if (over) {
        warn.textContent = "Số lượng xuất vượt tồn hiện có (" + nf.format(cur) + " " + d.unit + "). Phiếu này sẽ bị từ chối.";
        warn.hidden = false;
      } else if (!isIn && q > 0 && after <= min) {
        warn.textContent = "Sau phiếu này tồn kho chạm mức tối thiểu (" + nf.format(min) + " " + d.unit + "), nên lên kế hoạch nhập thêm.";
        warn.hidden = false;
      } else {
        warn.hidden = true;
      }
    }
    sel.addEventListener("change", update);
    qty.addEventListener("input", update);
    price.addEventListener("input", update);
    update();
  }

  /* ---------------------------------------------------------------- biểu đồ, bộ lọc ngày, in, menu di động, thông báo */
  function initChartTabs() {
    $$("[data-chart-tab]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        $$("[data-chart-tab]").forEach(function (b) { b.setAttribute("aria-pressed", String(b === btn)); });
        $$("[data-chart]").forEach(function (c) { c.hidden = c.dataset.chart !== btn.dataset.chartTab; });
      });
    });
  }
  function initPresets() {
    var from = $("[data-date-from]"), to = $("[data-date-to]");
    if (!from || !to) return;
    var iso = function (d) {
      return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    };
    $$("[data-preset]").forEach(function (b) {
      b.addEventListener("click", function () {
        var now = new Date(), start = new Date(now), p = b.dataset.preset;
        if (p === "month") start = new Date(now.getFullYear(), now.getMonth(), 1);
        else if (p !== "today") start.setDate(now.getDate() - (+p - 1));
        from.value = iso(start);
        to.value = iso(now);
        fire(from, "change");
      });
    });
  }
  function initMisc() {
    $$("[data-print]").forEach(function (b) { b.addEventListener("click", function () { window.print(); }); });
    if (document.body.hasAttribute("data-autoprint")) {
      window.addEventListener("load", function () { setTimeout(function () { window.print(); }, 400); });
    }
    $$("[data-nav-toggle]").forEach(function (b) {
      b.addEventListener("click", function () { document.body.classList.toggle("nav-open"); });
    });
    $$("[data-nav-close]").forEach(function (b) {
      b.addEventListener("click", function () { document.body.classList.remove("nav-open"); });
    });
    $$(".toast").forEach(function (t) {
      var close = function () { t.classList.add("leaving"); setTimeout(function () { t.remove(); }, 260); };
      var btn = $("[data-toast-close]", t);
      if (btn) btn.addEventListener("click", close);
      setTimeout(close, 5000);
    });
  }

  initConfirm();
  initLive();
  $$("select[data-combobox]").forEach(makeCombo);
  initStockPreview();
  initChartTabs();
  initPresets();
  initMisc();
})();
