"""Артисти зі структурованих даних: кожен випадок — реальний приклад із живого обходу 2026-10-02."""
import types
import unittest

import json
import tempfile
from pathlib import Path

from .artists import Artist, Dictionary, display, from_description, from_source, from_title, has_proper, key, llm_fill, settle, split_pair


def names(raw, title="Подія", venues=(), source=""):
    return [a.name for a in from_source(raw, title, list(venues), source)]


class FromSource(unittest.TestCase):
    def test_karabas_performer_is_title_copy(self):
        raw = {"performer": {"@type": "MusicGroup", "name": "Jerry Heil"}}
        self.assertEqual(names(raw, "Jerry Heil", source="karabas"), [])

    def test_other_source_keeps_performer_equal_to_title(self):
        raw = {"performer": {"@type": "PerformingGroup", "name": "ДахаБраха"}}
        self.assertEqual(names(raw, "ДахаБраха", source="badseller"), ["ДахаБраха"])

    def test_touring_troupe_is_artist(self):
        raw = {"performer": {"@type": "PerformingGroup", "name": "МУР"},
               "organizer": {"name": "Театральна мансарда"}}
        self.assertEqual(names(raw, "Нова вистава", ["Театральна мансарда"], "badseller"), ["МУР"])

    def test_venue_theatre_dropped_by_name(self):
        raw = {"performer": {"name": "Театр Актор"}, "organizer": {"name": "Театр «Актор»"}}
        self.assertEqual(names(raw, "Всі мої колишні", source="badseller"), [])

    def test_venue_theatre_dropped_by_slug(self):
        raw = {"performer": {"name": "Національна оперета України",
                             "url": "https://badseller.net/afisha/vykonavets/kyyivskyy-teatr-operety"},
               "organizer": {"name": "Київський національний академічний театр оперети",
                             "url": "https://badseller.net/afisha/kyiv/zal/kyyivskyy-teatr-operety"}}
        self.assertEqual(names(raw, "Чикаго", source="badseller"), [])

    def test_concert_ua_lineup_cleans_names_and_ignores_type(self):
        raw = {"performer": [{"@type": "Person", "name": "Арсен Пучков "},
                             {"@type": "Organization", "name": "Phil it"},
                             {"@type": "Person", "name": "Арсен Пучков"}]}
        self.assertEqual(names(raw, "СТЕНДАП СУБОТА", source="concert_ua"), ["Арсен Пучков", "Phil it"])

    def test_group_prefix_stripped(self):
        self.assertEqual(names({"performer": "Гурт Мертвий Півень"}), ["Мертвий Півень"])

    def test_promoter_is_not_artist(self):
        self.assertEqual(names({"performer": {"name": "Кайф Продакшн"}}, "Ван Панч"), [])

    def test_missing_or_junk(self):
        self.assertEqual(names({}), [])
        self.assertEqual(names({"performer": {"name": "x" * 200}}), [])


def item(*artist_names, lat=50.4, lon=30.5, venue="Зал", title="", category="music"):
    return types.SimpleNamespace(artists=[Artist(n) for n in artist_names], title=title, category=category,
                                 latitude=lat, longitude=lon, venue_name=venue)


class Settle(unittest.TestCase):
    def test_theatre_word_at_one_place_is_venue(self):
        items = [item("Театр на Подолі"), item("Театр на Подолі")]
        report = settle(items)
        self.assertEqual([i.artists for i in items], [[], []])
        self.assertEqual(report["dropped_as_venue"], {"Театр на Подолі": 2})

    def test_theatre_word_at_two_places_stays(self):
        items = [item("Театр Чорний квадрат", lat=50.4), item("Театр Чорний квадрат", lat=50.5)]
        settle(items)
        self.assertEqual([len(i.artists) for i in items], [1, 1])

    def test_venue_abbreviation_is_the_venue(self):
        it = item("НАДТ", venue="Національний академічний драматичний театр імені Лесі Українки")
        settle([it])
        self.assertEqual(it.artists, [])
        other = item("НАДТ", venue="Інший зал")
        settle([other])
        self.assertEqual(len(other.artists), 1)           # збіг лише з початковими літерами залу

    def test_coordinate_jitter_between_copies_does_not_make_a_venue_touring(self):
        a, b = item("Театр Візаві", lat=50.4501), item("Театр Візаві", lat=50.4504)
        settle([a, b])
        self.assertEqual((a.artists, b.artists), ([], []))

    def test_duplicate_copy_does_not_add_a_place(self):
        real, copy = item("Театр Візаві", lat=50.4), item("Театр Візаві", lat=50.9)
        copy.stage = "duplicate"
        settle([real, copy])
        self.assertEqual(real.artists, [])

    def test_orchestra_at_philharmonic_is_artist(self):
        name = "Академічний симфонічний оркестр Національної філармонії України"
        items = [item(name)]
        settle(items)
        self.assertEqual(len(items[0].artists), 1)

    def test_shipped_dictionary_loads_and_folds_genitive(self):
        items = [item("Бродячого Стендапу")]
        settle(items, Dictionary.load())
        self.assertEqual([a.name for a in items[0].artists], ["Бродячий Стендап"])

    def test_plain_name_at_one_place_stays(self):
        items = [item("МУР")]
        settle(items)
        self.assertEqual(len(items[0].artists), 1)

    def test_dictionary_forces_company_and_aliases(self):
        d = Dictionary({"Театр Чорний квадрат": {"kind": "company", "aliases": ["Чорний Квадрат"]}})
        items = [item("Чорний Квадрат")]
        settle(items, d)
        self.assertEqual([(a.name, a.how) for a in items[0].artists],
                         [("Театр Чорний квадрат", "dictionary")])

    def test_dictionary_venue_kind_drops_even_at_many_places(self):
        d = Dictionary({"Київська опера": {"kind": "venue"}})
        items = [item("Київська опера", lat=1), item("Київська опера", lat=2)]
        settle(items, d)
        self.assertEqual([i.artists for i in items], [[], []])

    def test_unknown_kind_rejected(self):
        with self.assertRaises(ValueError):
            Dictionary({"X": {"kind": "band"}})


D = Dictionary(seed=["Jerry Heil", "Ivan Liulenov", "Алла Волкова", "Анастасія Ткаченко",
                     "Олександр Пономарьов", "Михайло Хома", "Queen", "Скрябін", "СКАЙ"])


def title_names(title, category="music"):
    return [a.name for a in from_title(title, D, category)]


class FromTitle(unittest.TestCase):
    def test_known_whole_title(self):
        self.assertEqual(title_names("Jerry Heil"), ["Jerry Heil"])

    def test_unknown_whole_title_is_not_guessed(self):
        self.assertEqual(title_names("Невідомий Гурт"), [])

    def test_known_name_then_subtitle(self):
        self.assertEqual(title_names("Ivan Liulenov. НА БІС «БІС»"), ["Ivan Liulenov"])
        self.assertEqual(title_names("СКАЙ. 25 років на сцені"), ["СКАЙ"])

    def test_two_known_names(self):
        self.assertEqual(title_names("Олександр Пономарьов та Михайло Хома - Україна Переможе!"),
                         ["Олександр Пономарьов", "Михайло Хома"])
        self.assertEqual(title_names("Імпровізація з глядачами. Алла Волкова та Анастасія Ткаченко", "comedy"),
                         ["Алла Волкова", "Анастасія Ткаченко"])

    def test_join_with_one_known_part_needs_the_other_to_look_like_a_name(self):
        self.assertEqual(title_names("Олександр Пономарьов та шоу"), ["Олександр Пономарьов"])
        self.assertEqual(title_names("Олександр Пономарьов та Хтось Невідомий"),
                         ["Олександр Пономарьов", "Хтось Невідомий"])

    def test_known_name_inside_longer_title_in_any_case(self):
        d = Dictionary(seed=["Богдан Боярин"])
        self.assertEqual([a.name for a in from_title("Сольний Стендап Концерт Богдана Боярина", d, "comedy")],
                         ["Богдан Боярин"])

    def test_latin_ensemble_after_dash(self):
        self.assertEqual(title_names("QUEEN – Kyiv Mozart Orchestra"), ["Kyiv Mozart Orchestra"])
        self.assertEqual(title_names("Олег Скрипка та симфонічний оркестр"), [])

    def test_theme_title_drops_source_performer_found_in_title(self):
        raw = {"performer": {"name": "Людовіко Ейнауді та Ян Тірсен"}}
        self.assertEqual(names(raw, "Музика при свічках: Людовіко Ейнауді та Ян Тірсен",
                               source="badseller"), [])
        raw = {"performer": {"name": "Beast"}}
        self.assertEqual(names(raw, "Трибʼют Queen - гурт Beast", source="badseller"), ["Beast"])

    def test_explicit_group_marker_needs_no_dictionary(self):
        self.assertEqual(title_names("Гурт Мертвий Півень"), ["Мертвий Півень"])
        self.assertEqual(title_names("Гурт All Night (дует)"), ["All Night"])
        self.assertEqual(title_names("Гурт ЯРРА - Велесова Ніч"), ["ЯРРА"])

    def test_tribute_takes_group_after_marker_not_the_subject(self):
        self.assertEqual(title_names("Трибʼют Queen - гурт Beast"), ["Beast"])
        self.assertEqual(title_names("Триб’ют Ozzy Osbourne - гурт Beast - Rock Halloween"), ["Beast"])

    def test_tribute_without_marker_has_no_artist_even_if_subject_is_known(self):
        self.assertEqual(title_names("Queen. Tribute show"), [])
        self.assertEqual(title_names("Queen при свічках"), [])

    def test_category_without_performers(self):
        self.assertEqual(title_names("Jerry Heil", "conference"), [])


class FromTitleStrict(unittest.TestCase):
    def test_seed_name_in_play_title_is_not_trusted_but_manual_entry_is(self):
        d = Dictionary({"Kyiv Modern-Ballet": {"kind": "company"}}, seed=["Раду Поклітару"])
        got = [a.name for a in from_title("Kyiv Modern-Ballet. Лускунчик. Версія. Раду Поклітару", d, "art")]
        self.assertEqual(got, ["Kyiv Modern-Ballet"])
        self.assertEqual([a.name for a in from_title("Раду Поклітару", d, "music")], ["Раду Поклітару"])


class FromDescription(unittest.TestCase):
    STANDUP = ("Запрошуємо на вечір комедії. 1. Арсен Пучков @arsen.p 2. Раміль Янгулов @ramil "
               "3. Руслан Колесник @ruslan92.ua4. Андрій Бережко @andreyberezhko Ведучий: Євген Лещенко @lytsemirniy Де: Бочка")

    def test_standup_lineup_with_handles(self):
        got = from_description(self.STANDUP)
        self.assertEqual([a.name for a in got if a.role == "host"], ["Євген Лещенко"])
        self.assertEqual(sorted(a.name for a in got if a.role == "headliner"),
                         ["Андрій Бережко", "Арсен Пучков", "Раміль Янгулов", "Руслан Колесник"])

    def test_single_follow_us_handle_is_not_an_artist(self):
        self.assertEqual(from_description("Підписуйтесь на нас: Наш Instagram @bochka.pub"), [])
        self.assertEqual(from_description("Слідкуйте Іван Петренко @ivan.pet за новинами"), [])

    def test_single_handle_with_lineup_context_counts(self):
        self.assertEqual([a.name for a in from_description("Виступає Іван Петренко @ivan.pet")], ["Іван Петренко"])

    def test_cast_list_without_handles_is_ignored(self):
        self.assertEqual(from_description("У ролях: Петро Миронов, Віктор Кожевніков."), [])


class SettleTitles(unittest.TestCase):
    def test_karabas_title_confirmed_by_other_source(self):
        a = item("Vøvk", title="Vøvk")
        a.artists = [Artist("Vøvk", how="source")]
        b = item(title="Vøvk")
        settle([a, b])
        self.assertEqual([x.name for x in b.artists], ["Vøvk"])

    def test_unconfirmed_title_stays_empty(self):
        b = item(title="Vøvk")
        settle([b])
        self.assertEqual(b.artists, [])

    def test_venue_theatre_is_not_learned_from(self):
        a = item("Театр на Подолі", title="Вистава")
        b = item(title="Театр на Подолі")
        settle([a, b])
        self.assertEqual(b.artists, [])


def event(title, text="", category="music", venue="Зал"):
    return types.SimpleNamespace(artists=[], title=title, text=text, description=text, category=category,
                                 latitude=50.4, longitude=30.5, venue_name=venue)


def answer(*rows):
    """Відповідь моделі: rows — списки виконавців по подіях партії, за порядком."""
    return json.dumps({"events": [{"n": n, "artists": r} for n, r in enumerate(rows, 1)]}, ensure_ascii=False)


class DuplicateNames(unittest.TestCase):
    def test_parenthetical_does_not_split_one_person(self):
        self.assertEqual(key("Крістін Мілворд (Kristine Milward)"), key("Крістін Мілворд"))
        self.assertEqual(display("Крістін Мілворд (Kristine Milward)"), "Крістін Мілворд")
        self.assertEqual(names({"performer": [{"name": "Крістін Мілворд (Kristine Milward)"}, {"name": "Крістін Мілворд"}]}),
                         ["Крістін Мілворд"])

    def test_pair_of_people_is_two_artists_but_a_collective_is_one(self):
        self.assertEqual(split_pair("Алла Волкова та Анастасія Ткаченко"), ["Алла Волкова", "Анастасія Ткаченко"])
        self.assertEqual(split_pair("Бампер і Сус"), ["Бампер і Сус"])
        self.assertEqual(split_pair("Жадан і Собаки"), ["Жадан і Собаки"])
        self.assertEqual(split_pair("Наталія та Кирило Май"), ["Наталія та Кирило Май"])
        self.assertEqual(names({"performer": {"name": "Павло Ільницький та Іванка Червінська"}}),
                         ["Павло Ільницький", "Іванка Червінська"])

    def test_phrase_fragment_without_a_capital_is_not_an_artist(self):
        self.assertFalse(has_proper("заслужена працівниця"))
        self.assertTrue(has_proper("ансамблю класичної музики Фрески"))
        self.assertEqual(names({"performer": {"name": "заслужена працівниця"}}), [])

    def test_shipped_aliases_fold_the_reported_duplicate(self):
        d = Dictionary.load()
        items = [item("Київський Mozart Orchestra"), item("Kyiv Mozart Orchestra")]
        settle(items, d)
        self.assertEqual([[a.name for a in i.artists] for i in items], [["Kyiv Mozart Orchestra"]] * 2)
        self.assertEqual(d.lookup("Київський Mozart Orchestra")[0], "Kyiv Mozart Orchestra")

    def test_llm_pair_is_split_and_each_half_needs_the_quote(self):
        it = event("Вечір", "Виступають Алла Волкова та Анастасія Ткаченко.", category="comedy")
        llm_fill([it], lambda p: answer([{"name": "Алла Волкова та Анастасія Ткаченко",
                                          "evidence": "Алла Волкова та Анастасія Ткаченко"}]),
                 cache_path=Path(tempfile.mkdtemp()) / "c.json")
        self.assertEqual([a.name for a in it.artists], ["Алла Волкова", "Анастасія Ткаченко"])


class ArtistsSql(unittest.TestCase):
    def sql(self, *a, **kw):
        from .emit import artists_sql
        return artists_sql(*a, **kw)

    def ev(self, *people):
        import uuid
        return types.SimpleNamespace(event_id=uuid.UUID(int=1), artists=list(people))

    def test_upsert_link_and_full_replace(self):
        out = self.sql([self.ev(Artist("Арсен Пучков", role="host", how="lineup", confidence=0.9))])
        self.assertIn("insert into public.artists", out)
        self.assertIn("'арсен пучков'", out)
        self.assertIn("on conflict (key) do update", out)
        self.assertIn("join public.events e on e.id = v.event_id::uuid", out)       # подія могла не вставитись
        self.assertIn("ea.how <> 'llm'", out)                                           # без моделі її рядки не чіпаємо
        self.assertNotIn("ea.how <> 'llm'", self.sql([self.ev(Artist("X Y"))], replace_llm=True))

    def test_event_without_artists_still_clears_stale_links(self):
        out = self.sql([self.ev()])
        self.assertIn("delete from public.event_artists", out)
        self.assertNotIn("insert into", out)

    def test_same_artist_twice_in_batch_keeps_best_source_and_quotes_are_escaped(self):
        out = self.sql([self.ev(Artist("Д'Артаньян", how="llm"), Artist("Д'Артаньян", how="dictionary", kind="person"))])
        self.assertEqual(out.count("on conflict (key)"), 1)
        self.assertIn("'Д''Артаньян'", out)
        self.assertIn("'manual'", out)
        self.assertNotIn("'llm')", out.split("insert into public.event_artists")[0])


class PruneArtists(unittest.TestCase):
    def test_orphans_without_follows_are_pruned_and_guarded(self):
        from .emit import prune_artists_sql
        sql = prune_artists_sql()
        self.assertIn("to_regclass('public.artists') is not null", sql)       # база без міграції не падає
        self.assertIn("not exists (select 1 from public.event_artists", sql)
        self.assertIn("public.follows f where f.target_kind = 'artist'", sql)  # підписник утримує артиста


class SettleBrands(unittest.TestCase):
    def test_brand_in_description_alone_is_not_an_artist(self):
        """«Бродячий Стендап» стоїть в описах чужих шоу того ж промоутера: згадка не доводить виступу."""
        d = Dictionary({"Бродячий Стендап": {"kind": "show", "aliases": ["Бродячого Стендапу"]}})
        it = event("Комедійне шоу Не Проблема", "Від «Бродячого Стендапу».", category="comedy")
        settle([it], d)
        self.assertEqual(it.artists, [])


class LlmFill(unittest.TestCase):
    def run_fill(self, items, reply, **kw):
        calls = []

        def ask(prompt):
            calls.append(prompt)
            if isinstance(reply, Exception):
                raise reply
            return reply

        with tempfile.TemporaryDirectory() as tmp:
            stats = llm_fill(items, ask, cache_path=Path(tmp) / "c.json", **kw)
        return stats, calls

    def test_quote_in_other_case_is_accepted(self):
        it = event("Вечір", "Приходьте на концерт Наталії Могилевської у Києві.")
        self.run_fill([it], answer([{"name": "Наталія Могилевська", "role": "headliner",
                                     "evidence": "концерт Наталії Могилевської"}]))
        self.assertEqual([(a.name, a.how) for a in it.artists], [("Наталія Могилевська", "llm")])

    def test_invented_name_or_foreign_quote_is_rejected(self):
        it = event("Вечір", "Приходьте на концерт.")
        self.run_fill([it], answer([{"name": "Хтось", "evidence": "Хтось співає"},          # цитати в тексті немає
                                    {"name": "Хтось", "evidence": "Приходьте на концерт."}]))   # цитата є, імені в ній немає
        self.assertEqual(it.artists, [])

    def test_quote_must_come_from_this_event_not_neighbour(self):
        a, b = event("А", "Виступає Арсен Пучков."), event("Б", "Без імен.")
        self.run_fill([a, b], answer([], [{"name": "Арсен Пучков", "evidence": "Виступає Арсен Пучков."}]))
        self.assertEqual(b.artists, [])

    def test_tribute_subject_is_rejected(self):
        it = event("Queen при свічках", "Queen при свічках у виконанні струнного квартету.")
        self.run_fill([it], answer([{"name": "Queen", "evidence": "Queen при свічках"}]))
        self.assertEqual(it.artists, [])

    def test_venue_and_promoter_are_dropped(self):
        it = event("Вечір", "Вистава в Театрі на Подолі. Організатор Кайф Продакшн.")
        self.run_fill([it], answer([{"name": "Театр на Подолі", "evidence": "Вистава в Театрі на Подолі"},
                                    {"name": "Кайф Продакшн", "evidence": "Організатор Кайф Продакшн"}]))
        self.assertEqual(it.artists, [])

    def test_only_events_without_artists_in_performer_categories_are_asked(self):
        done = event("А", "Текст")
        done.artists = [Artist("Хтось")]
        expo = event("Виставка", "Текст", category="tours")
        todo = event("Б", "Текст")
        stats, calls = self.run_fill([done, expo, todo], answer([]))
        self.assertEqual((stats["targets"], len(calls)), (1, 1))
        self.assertNotIn("Виставка", calls[0])

    def test_cast_list_in_a_play_is_dropped_but_single_performer_stays(self):
        cast = event("Вистава", "У ролях: Петро Миронов, Віктор Кожевніков.", category="art")
        self.run_fill([cast], answer([{"name": "Петро Миронов", "evidence": "У ролях: Петро Миронов"},
                                      {"name": "Віктор Кожевніков", "evidence": "Віктор Кожевніков."}]))
        self.assertEqual(cast.artists, [])
        solo = event("Монодрама", "Грає Інна Гончарова.", category="art")
        self.run_fill([solo], answer([{"name": "Інна Гончарова", "evidence": "Грає Інна Гончарова."}]))
        self.assertEqual([a.name for a in solo.artists], ["Інна Гончарова"])

    def test_show_title_is_not_an_artist_unless_manual_brand(self):
        it = event("Комедійне Шоу Не Проблема", "Комедійне Шоу Не Проблема. Квитки.", category="comedy")
        self.run_fill([it], answer([{"name": "Не Проблема", "evidence": "Комедійне Шоу Не Проблема"}]))
        self.assertEqual(it.artists, [])
        brand = event("Дизель Шоу. До Дня Козацтва", "Дизель Шоу приїжджає.", category="comedy")
        self.run_fill([brand], answer([{"name": "Дизель Шоу", "evidence": "Дизель Шоу приїжджає."}]),
                      dictionary=Dictionary({"Дизель Шоу": {"kind": "show"}}))
        self.assertEqual([a.name for a in brand.artists], ["Дизель Шоу"])

    def test_cache_means_second_run_is_free(self):
        calls = []
        reply = answer([{"name": "Арсен Пучков", "evidence": "Виступає Арсен Пучков."}])
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / "c.json"
            for _ in range(2):
                it = event("А", "Виступає Арсен Пучков.")
                llm_fill([it], lambda p: calls.append(p) or reply, cache_path=cache)
                self.assertEqual([a.name for a in it.artists], ["Арсен Пучков"])
        self.assertEqual(len(calls), 1)

    def test_batches_and_transport_failure(self):
        items = [event(f"Подія {n}", "Текст") for n in range(10)]
        stats, calls = self.run_fill(items, RuntimeError("мережа"))
        self.assertEqual((len(calls), stats["errors"]), (2, 2))        # 8 + 2
        self.assertTrue(all(i.artists == [] for i in items))

    def test_garbage_reply_is_a_failure_not_a_crash(self):
        it = event("А", "Текст")
        stats, _ = self.run_fill([it], "вибачте, не можу")
        self.assertEqual((stats["errors"], it.artists), (1, []))


if __name__ == "__main__":
    unittest.main()
