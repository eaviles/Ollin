#!/bin/zsh
#
# Scripts/guide-coverage.sh: check that the Guide teaches what Ollin ships.
#
#   Scripts/guide-coverage.sh            # check, exit nonzero on any error
#   Scripts/guide-coverage.sh --list     # also print every row and its depth
#
# The Guide's promise is that no capability is merely named in a table: each one
# is explained in a chapter with a figure a reader can run. That promise used to
# rest on a habit, and habits lose. Seven feature slices shipped in two days at
# the end of July 2026, each got its one-line matrix row, and every audit stayed
# green because a row existed. This script is the check that habit was missing.
#
# It reads the feature-coverage matrix in Guide/PLAN.md and enforces five rules:
#
#   1. Every page under Docs/ (except the README indexes) has a matrix row.
#   2. Every Docs page a row names actually exists.
#   3. No row's depth is `pointed`, unless the Guide debt ledger in PLAN.md
#      names the chapter it is owed to. `pointed` is a promise to teach, not a
#      resting place: `shown` is the floor for anything that shipped, `taught`
#      is the goal.
#   4. Every Docs page is linked from at least one numbered chapter, so a reader
#      can reach the reference from the narrative and not just from the index.
#   5. Every Docs page has a row in Appendix D, the complete-toolbox tables.
#
# Debt rows are reported on every run even when they are legal, because the
# point of writing debt down is that somebody sees it.
#
# Run it before committing anything that ships a user-facing capability; it is
# step 5 of the ship checklist in CLAUDE.md, and part of the ollin-docs-audit
# skill. Guide authoring conventions live in Guide/AUTHORING.md.

cd "$(dirname "$0")/.." || exit 1

emulate -L zsh
setopt no_nomatch

plan=Guide/PLAN.md
appendix=Guide/D-CompleteToolbox.md
list_rows=0
[[ "$1" == "--list" ]] && list_rows=1
[[ "$1" == "--help" || "$1" == "-h" ]] && { sed -n '3,30p' "$0" | sed 's|^# \?||'; exit 0 }

errors=0
notes=0
fail() { print -u2 "guide-coverage: $1"; (( errors++ )) }
note() { print "guide-coverage: $1"; (( notes++ )) }

[[ -f $plan ]] || { print -u2 "guide-coverage: $plan not found"; exit 2 }
[[ -f $appendix ]] || { print -u2 "guide-coverage: $appendix not found"; exit 2 }

# ---------------------------------------------------------------- the matrix
# Normalize the table to capability<TAB>home<TAB>depth, dropping the header and
# the separator. A row's capability cell names its Docs page, either as the key
# (`Core/Sketch.md`) or inside the parenthetical of a capability that shares a
# page (`… in Drawing/Drawing.md`).
rows=$(awk -F'|' '
    /^## Feature-coverage matrix/ { inside = 1; next }
    inside && /^## /              { exit }
    inside && /^\| / && $0 !~ /^\|[- ]*-/ && $2 !~ /^ *Capability/ {
        cap = $2; home = $3; depth = $4
        gsub(/^[ \t]+|[ \t]+$/, "", cap)
        gsub(/^[ \t]+|[ \t]+$/, "", home)
        gsub(/^[ \t]+|[ \t]+$/, "", depth)
        print cap "\t" home "\t" depth
    }' $plan)

[[ -n $rows ]] || { print -u2 "guide-coverage: no matrix rows found in $plan"; exit 2 }

# ------------------------------------------------------------ the debt ledger
# Capability<TAB>owed-to<TAB>since. A `pointed` row is legal only with an entry
# here, and an entry has to name a chapter.
debt=$(awk -F'|' '
    /^## Guide debt/ { inside = 1; next }
    inside && /^## /  { exit }
    inside && /^\| / && $0 !~ /^\|[- ]*-/ && $2 !~ /^ *Capability/ {
        cap = $2; owed = $3; since = $4
        gsub(/^[ \t]+|[ \t]+$/, "", cap)
        gsub(/^[ \t]+|[ \t]+$/, "", owed)
        gsub(/^[ \t]+|[ \t]+$/, "", since)
        print cap "\t" owed "\t" since
    }' $plan)

typeset -A debt_owed debt_since
for line in ${(f)debt}; do
    [[ -n $line ]] || continue
    parts=("${(@ps:\t:)line}")
    debt_owed[${parts[1]}]=${parts[2]}
    debt_since[${parts[1]}]=${parts[3]}
    if ! print -r -- ${parts[2]} | grep -qiE '(ch\.? *[0-9]+|appendix)'; then
        fail "debt row '${parts[1]}' does not name the chapter it is owed to"
    fi
    if [[ ${parts[3]} != [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] ]]; then
        fail "debt row '${parts[1]}' needs a since-date as YYYY-MM-DD, found '${parts[3]}'"
    fi
done

# ------------------------------------------------------- rows: depth and pages
typeset -A page_row
typeset -a pointed_rows
row_count=0

for line in ${(f)rows}; do
    [[ -n $line ]] || continue
    parts=("${(@ps:\t:)line}")
    capability=${parts[1]}
    home=${parts[2]}
    depth=${parts[3]}
    (( row_count++ ))

    [[ -n $home ]] || fail "row '$capability' has no Guide home"

    # Judge the depth *token* only: the word before the note, so a row reading
    # `taught (… the rest named + pointed)` is taught and its note is free to say
    # which sub-items are not. A compound token ("taught/pointed by tracker") is
    # judged by its weakest part, or the rule is avoidable by prefixing "taught".
    token=${${depth%% *}%%\(*}
    case ${token:l} in
        *pointed*)
            pointed_rows+=("$capability")
            if [[ -n ${debt_owed[$capability]} ]]; then
                note "debt: '$capability' is owed a section in ${debt_owed[$capability]}, waiting since ${debt_since[$capability]}"
            else
                fail "row '$capability' is still 'pointed'. A shipped capability needs at least"$'\n'\
"    'shown' (a chapter mention plus a worked example) in the commit that ships it."$'\n'\
"    If this session genuinely cannot teach it, add it to the Guide debt ledger in"$'\n'\
"    $plan with the chapter it is owed to."
            fi
            ;;
        taught*) ;;
        shown*)  ;;
        "")      fail "row '$capability' has no depth" ;;
        *)       fail "row '$capability' has an unknown depth '$depth'" ;;
    esac

    # Rule 2: every Docs page a row names has to exist.
    for page in ${(f)"$(print -r -- $capability | grep -o '[A-Za-z0-9_/-]*\.md')"}; do
        [[ -n $page ]] || continue
        if [[ -f Docs/$page ]]; then
            page_row[$page]=$capability
        else
            fail "row '$capability' names Docs/$page, which does not exist"
        fi
    done

    (( list_rows )) && printf '  %-10s %-22s %s\n' "${depth%% *}" "$home" "$capability"
done

# ------------------------------------------------- pages: rows, chapters, D
chapter_links=$(grep -ho 'Docs/[A-Za-z0-9_/-]*\.md' Guide/[0-9]*.md \
                | sed 's|^Docs/||' | sort -u)
appendix_links=$(grep -ho 'Docs/[A-Za-z0-9_/-]*\.md' $appendix \
                 | sed 's|^Docs/||' | sort -u)

# `**/` already matches zero directories, so this covers Docs/Swift.md too.
# (Never name the loop variable `path`: in zsh it is tied to $PATH.)
page_count=0
for docpage in Docs/**/*.md; do
    [[ -f $docpage ]] || continue
    [[ ${docpage:t} == README.md ]] && continue
    page=${docpage#Docs/}
    (( page_count++ ))

    # Rule 1.
    [[ -n ${page_row[$page]} ]] || \
        fail "Docs/$page has no row in the feature-coverage matrix in $plan"

    # Rule 4.
    print -r -- $chapter_links | grep -qxF -- "$page" || \
        fail "Docs/$page is not linked from any numbered chapter (add it to a 'Go deeper' list)"

    # Rule 5.
    print -r -- $appendix_links | grep -qxF -- "$page" || \
        fail "Docs/$page has no row in $appendix"
done

# ------------------------------------------------------------------- verdict
print "guide-coverage: $row_count matrix rows covering $page_count Docs pages"
if (( errors )); then
    print -u2 "guide-coverage: $errors problem$( (( errors == 1 )) || print s ) found"
    exit 1
fi
if (( ${#pointed_rows} )); then
    print "guide-coverage: ${#pointed_rows} row$( (( ${#pointed_rows} == 1 )) || print s )" \
          "owed a chapter section (see the Guide debt ledger in $plan)"
fi
print "guide-coverage: ok"
exit 0
