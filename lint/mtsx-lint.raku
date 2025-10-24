#!/usr/bin/env raku
use v6;
use JSON::Fast;
use File::Find;
use File::Spec;
use Cwd;

# Linter (default lenient). Enhanced advanced-keyword detection and perf heuristics.

my $DEFAULT_MODE = 'lenient';

# Expanded list of advanced keywords / constructs to look for (heuristic)
my @ADVANCED_FEATURE_KEYWORDS = <matchEndFirst mustMatchEnd parseColor group_linkAll group_link startTagContains EndMatcher frontMatter match contains childrenStyle lang codeBlock inlineStyle urlRegex urlMatchers footnote linkRefDef specialMark colors startTagContains htmlMatchers namespace attrName propKey propVal parseColor_auto parseColor_RGB parseColor_RGBA parseColor_HSL parseColor_HSLA group childrenStyle>;

sub run-java-validate(Str $jar, Str $pattern) {
    my $cmd = qq[java -jar "$jar" --validate "$pattern" 2>&1];
    my $out = qx($cmd);
    if $out.chars {
        try { return from-json($out) } CATCH { return { ok => Bool(0), reason => $out } }
    } else {
        return { ok => Bool(1) };
    }
}

sub index-to-linecol(Str $text, Int $idx) {
    my @lines = $text.substr(0, $idx).split(/\r?\n/);
    my $line = @lines.elems;
    my $col = @lines[*-1].chars + 1;
    return { line => $line, col => $col };
}

sub sanitize-for-trailing(Str $text) {
    my $out = '';
    my $i = 0; my $n = $text.chars;
    my $state = 'N';
    while $i < $n {
        my $ch = $text.substr($i,1);
        if $state eq 'N' {
            if $ch ~~ /['"`]/ { $state = $ch; $out ~= ' '; $i++ ; next }
            if $ch eq '/' && $i+1 < $n && $text.substr($i+1,1) eq '/' { $state = 'L'; $out ~= '  '; $i+=2; next }
            if $ch eq '/' && $i+1 < $n && $text.substr($i+1,1) eq '*' { $state = 'B'; $out ~= '  '; $i+=2; next }
            $out ~= $ch; $i++; next;
        }
        if $state eq 'L' {
            if $ch eq "\n" { $state = 'N'; $out ~= "\n"; $i++; next }
            $out ~= ' '; $i++; next;
        }
        if $state eq 'B' {
            if $ch eq '*' && $i+1 < $n && $text.substr($i+1,1) eq '/' { $state = 'N'; $out ~= '  '; $i+=2; next }
            $out ~= ' '; $i++; next;
        }
        if $state ~~ /['"`]/ {
            if $ch eq '\\' && $i+1 < $n { $out ~= '  '; $i+=2; next }
            if $ch eq state { $state = 'N'; $out ~= ' '; $i++; next }
            $out ~= ' '; $i++; next;
        }
    }
    return $out;
}

sub analyze-inline(Str $body) {
    my @all = $body.match: / \(\? [^)]+ \) /x;
    return 'ok' if @all.elems == 0;
    if @all.elems == 1 && $body ~~ /^ \(\? [^)]+ \) /x {
        if $body ~~ /^ \(\? [a-zA-Z]+ \) /x { return 'global' }
    }
    return 'complex';
}

# Enhanced perf-smell heuristic
sub perf-smell(Str $pattern) {
    # Backreference numeric or named
    return True if $pattern ~~ /\\\d/;
    return True if $pattern ~~ /\\k<\w+>/;
    # Lookaround assertions
    return True if $pattern ~~ /\(\?\<=|\(\?\<!|\(\?\=|\(\?\!/;
    # Possessive quantifiers
    return True if $pattern ~~ /\+\+|\*\+|\?\+/;
    # Nested quantifiers or group followed by quantifier
    return True if $pattern ~~ /\([^\)]*[+*?][^\)]*\)[+*?]/;
    # Open upper bound quantifiers {m,}
    return True if $pattern ~~ /\{\s*\d+\s*,\s*\}/;
    # Large bounded quantifiers like {100,} considered risky
    return True if $pattern ~~ /\{\s*\d{2,}\s*,/;
    # Consecutive greedy wildcards or repeated wildcards
    return True if $pattern ~~ /\.\*\.\*/;
    return False;
}

# CLI parsing
my $mode = $DEFAULT_MODE;
my $with_java = False;
my $jarpath = '';
my $json_out = False;
my @paths = <mtsx/**/*.mtsx lint/**>;

for @*ARGS -> $i {
    given $i {
        when '--mode' { $mode = @*ARGS.shift // $DEFAULT_MODE }
        when '--with-java' { $with_java = True; $jarpath = @*ARGS.shift // '' }
        when '--jar' { $jarpath = @*ARGS.shift; $with_java = True }
        when '--json' { $json_out = True }
        when /^--paths=(.+)/ { @paths = ~$0.split(' ') }
        default {
            unless $i ~~ /^--/ { @paths.push: $i }
        }
    }
}

# find files
sub git-ls() {
    try { qx(git ls-files).split(/\n/).grep(*.chars > 0) } CATCH { default { () } }
}

my @files;
my @git = git-ls();
if @git.elems {
    for @paths -> $pat {
        for @git -> $g {
            if $g ~~ /$pat/ { @files.push: $g }
        }
    }
    @files = @files.unique;
} else {
    for @paths -> $p {
        for qx(find . -path "$p" -type f 2>/dev/null).split(/\n/) -> $line {
            @files.push: $line if $line.chars;
        }
    }
    @files = @files.unique;
}

unless @files.elems {
    say 'No files to lint.';
    exit 0;
}

my @reports;
for @files -> $f {
    my $txt = slurp $f, :enc<utf8>;
    my @errors; my @warnings;

    # top header check
    my $has_require_header = $txt ~~ /^ \s* \/\/ \s* require \s+ MT \s* >= \s* ([\d\.]+) /x;

    # advanced keywords
    my @found_adv := ();
    for @ADVANCED_FEATURE_KEYWORDS -> $kw {
        # allow both exact and substring checks for token-like keywords
        if $txt.includes($kw) || $txt.includes($kw.substr(0,8)) {
            @found_adv.push: $kw;
        }
    }
    if @found_adv.elems && !$has_require_header {
        my $msg = "Detected advanced syntax keywords that may require newer MT. Found: {@found_adv.unique.join(', ')}. Consider adding a top comment like: // require MT >= 2.16.0";
        if $mode eq 'strict' { @errors.push: { kind => 'mt-version', message => $msg } }
        else { @warnings.push: { kind => 'mt-version', message => $msg } }
    }

    # trailing commas
    my $s = sanitize-for-trailing($txt);
    for $s.match:g(/,\s*[\]\}]/) -> $m {
        my $off = $/~.from.pos;
        my $lc = index-to-linecol($txt, $off);
        my $msg = "Trailing comma at line {$lc<line>}:{$lc<col>}";
        if $mode eq 'strict' { @errors.push: { kind => 'trailing', message => $msg, offset => $off } }
        else { @warnings.push: { kind => 'trailing', message => $msg, offset => $off } }
    }

    # deprecated fields
    if $txt ~~ / \b colors \b \s* : /x {
        my $pos = $txt.index-of('colors');
        my $msg = "Deprecated field 'colors' used";
        if $mode eq 'strict' { @errors.push: { kind => 'deprecated', message => $msg, offset => $pos } }
        else { @warnings.push: { kind => 'deprecated', message => $msg, offset => $pos } }
    }

    # include checks (heuristic)
    for $txt.matchAll(/ include \s* \( \s* ["'] ([\w\-\_\.]+) ["'] \s* \) /x) -> $mm {
        my $name = $mm[1];
        unless $txt.includes("defines") || $txt.includes($name) {
            my $pos = $/~.from.pos;
            my $msg = "include('$name') references undefined name (heuristic)";
            if $mode eq 'strict' { @errors.push: { kind => 'include', message => $msg, offset => $pos } }
            else { @warnings.push: { kind => 'include', message => $msg, offset => $pos } }
        }
    }

    # regex handling: extract literals and check perf
    for $txt.match:g(/ \/ (?: \\\\ . | \\[ [^\\]]* \\] | [^\/\\] )+ \/ [a-zA-Z]* /x) -> $m {
        my $lit = ~$m;
        my $off = $/~.from.pos;
        my $last = $lit.rindex('/');
        next if $last <= 0;
        my $body = $lit.substr(1, $last-1);
        my $flags = $lit.substr($last+1);
        my $local_perf = perf-smell($body);
        my $java_res = { ok => Bool(1), notes => [] , perfRisk => Bool($local_perf) };
        if $with_java && $jarpath.chars {
            $java_res = run-java-validate($jarpath, $body);
        }
        if $java_res<perfRisk>:exists && $java_res<perfRisk> {
            my $msg = "Regex may have performance issues: $lit";
            if $mode eq 'strict' { @errors.push: { kind => 'regex-perf', message => $msg, literal => $lit, offset => $off } }
            else { @warnings.push: { kind => 'regex-perf', message => $msg, literal => $lit, offset => $off } }
        }
    }

    @reports.push: { file => $f, errors => @errors, warnings => @warnings };
}

# map offsets to line/col
for @reports -> $r {
    my $txt = slurp $r<file>, :enc<utf8>;
    for $r<errors> -> $e {
        if $e<offset>:exists {
            my $lc = index-to-linecol($txt, $e<offset>);
            $e<line> = $lc<line>; $e<col> = $lc<col>;
        }
    }
    for $r<warnings> -> $w {
        if $w<offset>:exists {
            my $lc = index-to-linecol($txt, $w<offset>);
            $w<line> = $lc<line>; $w<col> = $lc<col>;
        }
    }
}

say to-json({ mode => $mode, with_java => $with_java, reports => @reports }, :pretty);
