<?php
// api_search.php -- HotCRP search-related API calls
// Copyright (c) 2008-2020 Eddie Kohler; see LICENSE.

class Search_API {
    static function search(Contact $user, Qrequest $qreq) {
        $topt = PaperSearch::search_types($user, $qreq->t);
        if (empty($topt) || ($qreq->t && !isset($topt[$qreq->t]))) {
            return new JsonResult(403, "Permission error.");
        }
        $t = $qreq->t ? : key($topt);

        $q = $qreq->q;
        if (isset($q)) {
            $q = trim($q);
            if ($q === "(All)")
                $q = "";
        } else if (isset($qreq->qa) || isset($qreq->qo) || isset($qreq->qx)) {
            $q = PaperSearch::canonical_query((string) $qreq->qa, (string) $qreq->qo, (string) $qreq->qx, $qreq->qt, $user->conf);
        } else {
            return new JsonResult(400, "Missing parameter.");
        }

        $search = new PaperSearch($user, ["t" => $t, "q" => $q, "qt" => $qreq->qt, "urlbase" => $qreq->urlbase, "reviewer" => $qreq->reviewer]);
        $pl = new PaperList($qreq->report ? : "pl", $search, ["sort" => true], $qreq);
        $pl->add_report_default_view();
        $pl->add_session_view();
        $ih = $pl->ids_and_groups();
        return ["ok" => true, "ids" => $ih[0], "groups" => $ih[1],
                "hotlist" => $pl->session_list_object()->info_string()];
    }

    static function fieldhtml(Contact $user, Qrequest $qreq, PaperInfo $prow = null) {
        if ($qreq->f === null) {
            return new JsonResult(400, "Missing parameter.");
        }
        if (!isset($qreq->q) && $prow) {
            $qreq->t = $prow->timeSubmitted > 0 ? "s" : "all";
            $qreq->q = $prow->paperId;
        } else if (!isset($qreq->q)) {
            $qreq->q = "";
        }

        $search = new PaperSearch($user, $qreq);
        $pl = new PaperList("empty", $search);
        if (isset($qreq->aufull)) {
            $pl->set_view("aufull", (bool) $qreq->aufull);
        }
        $response = $pl->column_json($qreq->f);

        $j = ["ok" => !empty($response["fields"])] + $response;
        foreach ($pl->message_set()->message_texts() as $m) {
            $j["errors"][] = $m;
        }
        if ($j["ok"] && $qreq->session && $qreq->post_ok()) {
            Session_API::setsession($user, $qreq->session);
        }
        return $j;
    }

    static function fieldtext(Contact $user, Qrequest $qreq, PaperInfo $prow = null) {
        if ($qreq->f === null) {
            return new JsonResult(400, "Missing parameter.");
        }

        if (!isset($qreq->q) && $prow) {
            $qreq->t = $prow->timeSubmitted > 0 ? "s" : "all";
            $qreq->q = $prow->paperId;
        } else if (!isset($qreq->q)) {
            $qreq->q = "";
        }
        $search = new PaperSearch($user, $qreq);
        $pl = new PaperList("empty", $search);
        $response = $pl->text_json($qreq->f);

        $j = ["ok" => !empty($response), "data" => $response];
        foreach ($pl->message_set()->message_texts() as $m) {
            $j["errors"][] = $m;
        }
        return $j;
    }
}
