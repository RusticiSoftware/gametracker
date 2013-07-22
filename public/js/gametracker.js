var gametracker = gametracker || {};

(function () {
    "use strict";

    var modalOpts = {
        show: true,
        backdrop: false,
        keyboard: true
    };

    gametracker.newGameShown = function () {
        var p1, p2;
        p1 = $('#p1');
        p2 = $('#p2');

        p2.attr('selectedIndex', 1);

        $('#p1,#p2').change(function () {

            $("#p1 option[value='" + p2.data('oldVal') + "']").removeAttr("disabled");
            $("#p2 option[value='" + p1.data('oldVal') + "']").removeAttr("disabled");

            $("#p1 option[value='" + p2.val() + "']").attr("disabled", "disabled");
            $("#p2 option[value='" + p1.val() + "']").attr("disabled", "disabled");

            $.each(['#s1', '#w1', '#s2', '#w2'], function (i, op) {
                $(op).empty()
                    .append(new Option(p1.val(), p1.val()))
                    .append(new Option(p2.val(), p2.val()));
            });
            $.each(['#s3', '#w3'], function (i, op) {
                $(op).empty()
                    .append(new Option("", ""))
                    .append(new Option(p1.val(), p1.val()))
                    .append(new Option(p2.val(), p2.val()));
            });
            p1.data('oldVal', p1.val());
            p2.data('oldVal', p2.val());

        }).change();
    };

    gametracker.newDoublesGameShown = function () {
        var p1, p2, p3, p4;
        p1 = $('#p1');
        p2 = $('#p2');
        p3 = $('#p3');
        p4 = $('#p4');

        p2.attr('selectedIndex', 1);
        p3.attr('selectedIndex', 2);
        p4.attr('selectedIndex', 3);

        $('#p1, #p2, #p3, #p4').change(function(){

//    $.each([p1, p2, p3, p4], function(index, player){
//      $("#p1 option[value='" + player.data('oldVal') + "']").removeAttr("disabled");
//      $("#p2 option[value='" + player.data('oldVal') + "']").removeAttr("disabled");
//      $("#p3 option[value='" + player.data('oldVal') + "']").removeAttr("disabled");
//      $("#p4 option[value='" + player.data('oldVal') + "']").removeAttr("disabled");
//
//      $("#p1 option[value='" + player.val() + "']").attr("disabled","disabled");
//      $("#p2 option[value='" + player.val() + "']").attr("disabled","disabled");
//      $("#p3 option[value='" + player.val() + "']").attr("disabled","disabled");
//      $("#p4 option[value='" + player.val() + "']").attr("disabled","disabled");
//    });

            $.each(['#s1', '#s2', '#s3'], function (i, op){
                $(op).empty()
                    .append(new Option(p1.val(), p1.val()))
                    .append(new Option(p2.val(), p2.val()))
                    .append(new Option(p3.val(), p3.val()))
                    .append(new Option(p4.val(), p4.val()));
            });
            $.each(['#s4', '#s5'], function(i, op){
                $(op).empty()
                    .append(new Option("", ""))
                    .append(new Option(p1.val(), p1.val()))
                    .append(new Option(p2.val(), p2.val()))
                    .append(new Option(p3.val(), p3.val()))
                    .append(new Option(p4.val(), p4.val()));
            });

            $.each(['#w1', '#w2', '#w3'], function (i, op){
                $(op).empty()
                    .append(new Option('Team 1', 'team1'))
                    .append(new Option('Team 2', 'team2'));
            });
            $.each(['#w4', '#w5'], function(i, op){
                $(op).empty()
                    .append(new Option("", ""))
                    .append(new Option('Team 1', 'team1'))
                    .append(new Option('Team 2', 'team2'));
            });
            p1.data('oldVal',  p1.val() );
            p2.data('oldVal',  p2.val() );
            p3.data('oldVal',  p3.val() );
            p4.data('oldVal',  p4.val() );

        }).change();
    }

    $(document).ready(function () {
        $("#new_user").click(function (e) {
            if (e) {
                e.preventDefault();
            }

            $("#new_user_modal").modal(modalOpts);
        });

        $("#new_game").click(function (e) {
            if (e) {
                e.preventDefault();
            }

            var modalEl = $("#new_game_modal");
            modalEl.on("shown", gametracker.newGameShown);
            modalEl.modal(modalOpts)
        });

        $("#new_doubles_game").click(function (e) {
            if (e) {
                e.preventDefault();
            }

            var modalEl = $("#new_doubles_game_modal");

            modalEl.on("shown", gametracker.newDoublesGameShown);
            modalEl.modal(modalOpts);
        });
    });
})();