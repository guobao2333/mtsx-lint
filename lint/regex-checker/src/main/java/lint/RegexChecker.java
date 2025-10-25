package lint;

import java.util.*;
import java.util.regex.Pattern;
import java.util.regex.PatternSyntaxException;
import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import dk.brics.automaton.*;

// JSON result structures
class ValidateResult {
    boolean ok;
    String reason;
    List<String> notes;
    String jsFlags;
    boolean perfRisk;
}

class CompareResult {
    String status;
    String reason;
}

public class RegexChecker {
    static Gson gson = new GsonBuilder().disableHtmlEscaping().create();

    static class InlineAnalysis {
        boolean atStart = false;
        String flags = "";
        boolean complex = false;
    }

    static InlineAnalysis analyzeInline(String pattern) {
        InlineAnalysis r = new InlineAnalysis();
        java.util.regex.Matcher mm = java.util.regex.Pattern.compile("\\\\(\\?[^)]+\\)").matcher(pattern);
        boolean first = true;
        while (mm.find()) {
            String group = mm.group();
            int pos = mm.start();
            if (group.contains(":")) {
                r.complex = true;
            } else {
                String inner = group.substring(2, group.length()-1);
                if (pos == 0 && first) {
                    r.atStart = true;
                    r.flags = inner;
                } else {
                    r.complex = true;
                }
            }
            first = false;
        }
        return r;
    }

    // Stronger heuristic for performance-risk patterns
    static boolean detectPerfRisk(String pattern) {
        // numeric backreference like \1, \2
        if (pattern.matches("(?s).*\\\\\\\\\\d+.*")) return true;
        // named backref \k<name> or \k'name'
        if (pattern.matches("(?s).*\\\\\\\\k<[^>]+>.*") || pattern.matches("(?s).*\\\\\\\\k'[^']+'.*")) return true;
        // lookaround assertions (?<=, (?<!, (?=, (?! )
        if (pattern.matches("(?s).*\\(\\?<=.*|.*\\(\\?<!.*|.*\\(\\?=.*|.*\\(\\?!.*")) return true;
        // possessive quantifiers ++, *+, ?+ (Java-specific)
        if (pattern.matches("(?s).*[+*?]\\+.*")) return true;
        // nested quantifiers like (.+)+ or (.*)+ or (a+)+ or group followed by quantifier
        if (pattern.matches("(?s).*\\([^)]+[+*?][^)]+\\)[+*?].*")) return true;
        // group repeated with brace quantifier e.g. (..){m,}
        if (pattern.matches("(?s).*\\([^)]+\\)\\{\\s*\\d+\\s*,.*")) return true;
        // open upper bound {m,}
        if (pattern.matches("(?s).*\\{\\s*\\d+\\s*,\\s*\\}.*")) return true;
        // consecutive greedy wildcards or repeated wildcards
        if (pattern.matches("(?s).*\\.\\*.*\\.\\*.*")) return true;
        // long bounded quantifiers like {100,} considered risky
        if (pattern.matches("(?s).*\\{\\s*\\d{2,}\\s*,.*")) return true;
        return false;
    }

    static ValidateResult validateJavaRegex(String pattern) {
        ValidateResult res = new ValidateResult();
        res.notes = new ArrayList<>();
        InlineAnalysis ia = analyzeInline(pattern);
        if (ia.complex) {
            res.notes.add("contains inline flag constructs (scoped/toggling) that may not be portable");
        }
        try {
            Pattern.compile(pattern);
            res.ok = true;
        } catch (PatternSyntaxException e) {
            res.ok = false;
            res.reason = e.getMessage();
            return res;
        }
        if (ia.atStart && ia.flags != null && ia.flags.length() > 0) {
            StringBuilder jsf = new StringBuilder();
            for (char c : ia.flags.toCharArray()) {
                if ("imsu".indexOf(c) >= 0) jsf.append(c);
                else res.notes.add("inline flag '" + c + "' cannot be mapped automatically to JS flags");
            }
            res.jsFlags = jsf.toString();
        }
        res.perfRisk = detectPerfRisk(pattern);
        return res;
    }

    static CompareResult compareRegexUsingBrics(String a, String b) {
        CompareResult r = new CompareResult();
        try {
            RegExp ra = new RegExp(a);
            RegExp rb = new RegExp(b);
            Automaton aa = ra.toAutomaton();
            Automaton bb = rb.toAutomaton();
            aa.minimize();
            bb.minimize();

            // Use instance methods for set operations (compatible with multiple automaton versions)
            Automaton a_minus_b = aa.minus(bb); // strings in aa but not in bb
            Automaton b_minus_a = bb.minus(aa); // strings in bb but not in aa
            if (a_minus_b.isEmpty() && b_minus_a.isEmpty()) {
                r.status = "equal";
                return r;
            }
            if (a_minus_b.isEmpty()) { r.status = "subset"; return r; }
            if (b_minus_a.isEmpty()) { r.status = "superset"; return r; }

            Automaton inter = aa.intersection(bb);
            if (!inter.isEmpty()) { r.status = "overlap"; return r; }
            r.status = "disjoint";
            return r;
        } catch (IllegalArgumentException ex) {
            r.status = "unsupported";
            r.reason = "dk.brics.automaton cannot parse this regex (likely uses constructs outside regular subset): " + ex.getMessage();
            return r;
        } catch (Exception ex) {
            r.status = "unsupported";
            r.reason = "error while comparing: " + ex.getMessage();
            return r;
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 0) {
            System.err.println("Usage: RegexChecker --validate <pattern> | --compare <pat1> <pat2>");
            System.exit(2);
        }
        if ("--validate".equals(args[0]) && args.length >= 2) {
            String pattern = args[1];
            ValidateResult vr = validateJavaRegex(pattern);
            System.out.println(gson.toJson(vr));
            System.exit(vr.ok ? 0 : 2);
        } else if ("--compare".equals(args[0]) && args.length >= 3) {
            String a = args[1], b = args[2];
            CompareResult cr = compareRegexUsingBrics(a, b);
            System.out.println(gson.toJson(cr));
            if ("unsupported".equals(cr.status)) System.exit(3);
            System.exit(0);
        } else {
            System.err.println("Unknown args");
            System.exit(2);
        }
    }
}
