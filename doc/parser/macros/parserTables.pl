loadMacros("parserUtils.pl");

#############################################
#
#  For Parser example tables:
#

$BTT = MODES(TeX=>'{\tt ', Latex2HTML => $bHTML.'<TT>'.$eHTML, HTML => '<TT>');
$ETT = MODES(TeX=>'}', Latex2HTML => $bHTML.'</TT>'.$eHTML, HTML => '</TT>');

$BC = MODES(
  TeX=>'{\tt ',
  Latex2HTML => $bHTML.'<SMALL><I>'.$eHTML,
  HTML => '<SMALL><I>'
);
$EC = MODES(
  TeX=>'}',
  Latex2HTML => $bHTML.'</I></SMALL>'.$eHTML,
  HTML => '</I></SMALL>'
);

$LT = MODES(TeX => "<", Latex2HTML => "<", HTML => '&lt;');
$GT = MODES(TeX => ">", Latex2HTML => ">", HTML => '&gt;');

@rowOptions = (
  indent => 0,
  separation => 0,
  align => 'LEFT" NOWRAP="1',  # alignment hack to get NOWRAP
);

sub ParserRow {
  my $f = shift; my $t = '';
  Context()->clearError;
  my ($s,$err) = PG_restricted_eval($f);
  if (defined $s) {
    my $ss = $s;
    if (ref($s) && \&{$s->string}) {
      $t = '\('.$s->TeX.'\)';
      $s = $s->string;
    } elsif ($s !~ m/^[a-z]+$/i) {
      $t = '\('.Formula($s)->TeX.'\)';
      $s = Formula($s)->string;
    }
    $s =~ s/</$LT/g; $s =~ s/>/$GT/g;
    $s .= ' '.$BC.'('.$ss->class.' object)'.$EC if ref($ss) && \&{$ss->class};
  } else {
    $s = $BC. (Context()->{error}{message} || $err) . $EC;
    $t = '';
  }
  $f =~ s/</$LT/g; $f =~ s/>/$GT/g;
  my $row = Row([$BTT.$f.$ETT,$BTT.$s.$BTT,$t],@rowOptions);
  $row =~ s/\$/\${DOLLAR}/g;
  return $row;
}

sub ParserTable {
  my $table = 
    BeginTable(border=>1, padding=>20).
      Row([$BBOLD."Perl Code".$EBOLD,
           $BBOLD."Result".$EBOLD,
           $BBOLD.'\(\bf\TeX\) version'.$EBOLD],@rowOptions);
  foreach my $f (@_) {$table .= ParserRow($f)}
  $table .= EndTable();
  return $table;
}

sub Title {
  my $title = shift;

  MODES(
    TeX => "\\par\\centerline{\\bf $title}\\par\\nobreak\n",
    Latex2HTML => $bHTML.'<CENTER><H2>'.$title.'</H2></CENTER>'.$eHTML,
    HTML => '<CENTER><H2>'.$title.'</H2></CENTER>'
  );
}
