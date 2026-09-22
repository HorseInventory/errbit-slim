$(function () {
  $('input[type="checkbox"][data-show-when-checked]').change(function () {
    var el = $($(this).data("show-when-checked"));
    el.toggle($(this).is(":checked"));
  });
});
