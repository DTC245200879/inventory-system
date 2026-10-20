// Xác nhận trước khi xoá (không dùng onclick inline để tuân thủ CSP)
document.addEventListener("submit", function (e) {
  var msg = e.target.getAttribute("data-confirm");
  if (msg && !window.confirm(msg)) e.preventDefault();
});
