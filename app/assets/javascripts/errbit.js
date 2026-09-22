// App JS

$(function () {
  var currentTab = window.location.hash.replace("#", "") || "summary";

  function init() {
    activateTabbedPanels();

    activateSelectableRows();

    toggleProblemsCheckboxes();

    // On page apps/:app_id/edit
    $("a.copy_config").on("click", function () {
      $("select.choose_other_app").show().focus();
    });

    $("select.choose_other_app").on("change", function () {
      var loc = window.location;
      window.location.href = loc.protocol + "//" + loc.host + loc.pathname + "?copy_attributes_from=" + $(this).val();
    });

    bindProblemButtonsActions();

    $(".notice-pagination").each(function () {
      $.pjax.defaults = { timeout: 2000 };

      $("#content")
        .pjax(".notice-pagination a")
        .on("pjax:start", function () {
          $(".notice-pagination-loader").css("visibility", "visible");
          currentTab = $(".tab-bar ul li a.button.active").attr("rel");
        })
        .on("pjax:end", function () {
          activateTabbedPanels();
        });
    });
  }

  function activateTabbedPanels() {
    $(".tab-bar a").each(function () {
      var tab = $(this);
      var panel = $("#" + tab.attr("rel"));
      panel.addClass("panel");
      panel.find("h3").hide();
    });

    $(".tab-bar a").click(function () {
      activateTab($(this));
      return false;
    });
    activateTab($(".tab-bar ul li a.button[rel=" + currentTab + "]"));
  }

  function activateTab(tab) {
    tab = $(tab);
    var panel = $("#" + tab.attr("rel"));

    tab.closest(".tab-bar").find("a.active").removeClass("active");
    tab.addClass("active");

    // Update URL with hash fragment
    var hash = tab.attr("rel");
    if (hash && window.history && window.history.replaceState) {
      window.history.replaceState(null, null, "#" + hash);
    }
    // Update the .notice-pagination buttons by adding the hash fragment to the end of their URLs
    //   If there is already a hash fragment, replace it with the new one
    $(".notice-pagination a").each(function () {
      var href = $(this).attr("href");
      if (href && href.includes("#")) {
        $(this).attr("href", href.replace(/#.*$/, "#" + hash)); // Replace the current hash fragment with the new one
      } else if (href) {
        $(this).attr("href", href + "#" + hash); // Add the hash fragment to the end of the URL
      }
    });

    // If clicking into 'backtrace' tab, hide external backtrace
    if (tab.attr("rel") == "backtrace") {
      hide_external_backtrace();
    }

    $(".panel").hide();
    panel.show();
  }

  window.toggleProblemsCheckboxes = function () {
    var checkboxToggler = $("#toggle_problems_checkboxes");

    checkboxToggler.on("click", function () {
      $('input[name^="problems"]').each(function () {
        this.checked = checkboxToggler.get(0).checked;
      });
    });
  };

  window.bindProblemButtonsActions = function () {
    $("input[type=submit][data-action]").on("click", function () {
      $(this).closest("form").attr("action", $(this).attr("data-action"));
    });
  };

  function activateSelectableRows() {
    $(".selectable tr").click(function (event) {
      if (!["A", "INPUT", "BUTTON", "TEXTAREA"].includes(event.target.nodeName)) {
        var checkbox = $(this).find('input[name="problems[]"]').get(0);
        checkbox.checked = !checkbox.checked;
      }
    });
  }

  function hide_external_backtrace() {
    $("tr.toggle_external_backtrace").hide();
    $("td.backtrace_separator").show();
  }
  function show_external_backtrace() {
    $("tr.toggle_external_backtrace").show();
    $("td.backtrace_separator").hide();
  }
  // Show external backtrace lines when clicking separator
  $(document).on("click", "td.backtrace_separator span", show_external_backtrace);
  // Hide external backtrace on page load
  hide_external_backtrace();

  init();
});
