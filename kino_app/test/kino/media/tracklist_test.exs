defmodule Kino.Media.TracklistTest do
  use ExUnit.Case, async: true

  alias Kino.Media.Tracklist

  @vision_description """
  VISION Radio S06E28 — full show.

  00:00 VISION Radio Intro
  00:48 Forbidden Society - Addict (VIP) • VISION
  03:59 Forbidden Society - Picture Of Us (Enta Remix) • VISION
  07:43 Anaïs, Stylo G & Lady Leshurr - Strong Like Lion • UKF
  10:17 TI - Lost For Words • SOFA SOUND
  12:30 Waeys & Wingz - Yellowjacket • OVERVIEW
  14:40 Paimon - Callin me • EATBRAIN
  16:34 NUEQ - Mutate • DUB
  19:07 Flaco - Logic (Objectiv Remix) • CO LAB
  21:00 Lenzman - In My Mind feat IAMDDB (Break Remix) • THE NORTH QUARTER
  23:58 MARAH, Jessy Covets - LULA • DEADBEATS
  25:53 Spektiv & Morrow - Baddest • TRANSPARANT
  28:07 Tweakz & Regrowth - Tandem • NYX
  29:57 Logistics - Chant (Lens & Unglued Remix) • HOSPITAL
  31:49 Enei - Routine • CRITICAL
  34:01 UFO! X Meson - INKY • DUB
  37:18 Diverse - Tell Them • RIOT
  40:17 Myselor - Tat Tvam Asi • EVOLUTION CHAMBER
  44:44 Current Value - FARSIDE • MCR • VISION RADIO RELOAD
  49:11 Krafty Kuts - Friction • AGAINST THE GRAIN
  52:31 Sikka - Watch Dis • LIONDUB
  55:08 Teej & Felov - Anti Roller Roller Club • FLEXOUT
  57:20 Waeys & Klinical - If Only • OVERVIEW

  Follow VISION: https://example.com
  """

  test "parses the VISION Radio description into ordered entries" do
    entries = Tracklist.parse_description(@vision_description, 3604)

    assert length(entries) == 23
    assert %{"position" => 1, "start_seconds" => 0, "end_seconds" => 48} = hd(entries)

    farside = Enum.find(entries, &(&1["position"] == 19))
    assert farside["start_seconds"] == 44 * 60 + 44
    assert farside["artist"] == "Current Value"
    assert farside["title"] =~ "FARSIDE"

    last = List.last(entries)
    assert last["start_seconds"] == 57 * 60 + 20
    assert last["end_seconds"] == 3604
    assert last["artist"] == "Waeys & Klinical"
    assert last["title"] == "If Only • OVERVIEW"
  end

  test "prefers yt-dlp chapters when present" do
    info = %{
      "duration" => 120,
      "description" => "00:10 should be ignored",
      "chapters" => [
        %{"start_time" => 0.0, "end_time" => 48.0, "title" => "Intro"},
        %{"start_time" => 48.0, "end_time" => 120.0, "title" => "FS - Addict"}
      ]
    }

    assert [first, second] = Tracklist.from_ytdlp(info)

    assert %{"position" => 1, "start_seconds" => 0, "end_seconds" => 48, "label" => "Intro"} =
             first

    assert %{"artist" => "FS", "title" => "Addict"} = second
  end

  test "falls back to description and handles HH:MM:SS stamps" do
    entries = Tracklist.from_ytdlp(%{"description" => "1:02:03 Deep Cut", "duration" => 4000})
    assert [%{"start_seconds" => 3723, "title" => "Deep Cut", "artist" => nil}] = entries
  end

  test "returns [] when nothing parses" do
    assert Tracklist.from_ytdlp(%{"description" => "no stamps here"}) == []
    assert Tracklist.from_ytdlp(%{}) == []
  end
end
