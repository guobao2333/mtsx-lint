#!/usr/bin/env raku
use v6;
use JSON::Fast;
if @*ARGS != 2 {
    say "Usage: raku json-to-sarif.raku <input.json> <output.sarif>";
    exit 2;
}
my $in = @*ARGS[0]; my $out = @*ARGS[1];
my $obj = from-json(slurp $in, :enc<utf8>);
my @results;
for $obj<reports> -> $r {
    my $file = $r<file>;
    for $r<errors>.list -> $e {
        my $line = $e<line> // 1; my $col = $e<col> // 1;
        @results.push: { ruleId => $e<kind> // 'error', level => 'error', message => { text => $e<message> // '' }, locations => [ { physicalLocation => { artifactLocation => { uri => $file }, region => { startLine => $line, startColumn => $col } } } ] };
    }
    for $r<warnings>.list -> $w {
        my $line = $w<line> // 1; my $col = $w<col> // 1;
        @results.push: { ruleId => $w<kind> // 'warning', level => 'warning', message => { text => $w<message> // '' }, locations => [ { physicalLocation => { artifactLocation => { uri => $file }, region => { startLine => $line, startColumn => $col } } } ] };
    }
}
my $sar = { version => "2.1.0", $schema => "https://schemastore.azurewebsites.net/schemas/json/sarif-2.1.0.json", runs => [ { tool => { driver => { name => "mtsx-lint-raku" } }, results => @results } ] };
spurt to-json($sar, :pretty), $out;
say "Wrote SARIF -> $out";
