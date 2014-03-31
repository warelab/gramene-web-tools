package Grm::Web::Feedback;

use strict;
use warnings;

use Mojo::Base 'Mojolicious::Controller';

use Captcha::reCAPTCHA;
use Data::Dump 'dump';
use Email::Valid;
use Grm::Config;
use Grm::BugTracker;
use HTML::LinkExtractor;
use HTTP::Request;
use JSON::XS;
use LWP::UserAgent;
use Mail::Sendmail;
use Mail::SpamAssassin;
use Readonly;
use Text::StripAccents;

Readonly my $DOUBLE_NEWLINE        => "\n\n";
Readonly my $COMMENTS_MAX          => 10_000;
Readonly my $MAX_URLS              => 5;
Readonly my $RECIPIENTS            => 'feedback@gramene.org';
Readonly my $MANTIS_URL => 'http://www.warelab.org/bugs/view.php?id=';
Readonly my $BASE_URL => 'https://basecamp.com/1777593/api/v1/projects/606889';

# -------------------------------------------------------
sub captcha_keys {
    my $self         = shift;
    my $req          = $self->req;
    my $conf         = $self->config;
    my %captcha_keys = %{ $conf->{'feedback'}{'captcha_keys'} || {} };

    ( my $host = $req->headers->host ) =~ s/:\d+$//;
    $host = 'gramene.org';

    if ( defined $captcha_keys{ $host } ) {
        return $captcha_keys{ $host };
    }
    else {
        die "No captcha keys defined for host '$host'"
    }
}

# -------------------------------------------------------
sub form {
    my $self         = shift;
    my $req          = $self->req;
    my $captcha_keys = $self->captcha_keys;
    my $captcha      = Captcha::reCAPTCHA->new;
    my $captcha_html = $captcha->get_html($captcha_keys->{'public'});

    $self->layout('default');

    $self->render(
        captcha => $captcha_html,
    );
}

# -------------------------------------------------------
sub submit {
    my $self = shift;
    my $req  = $self->req;

    my @errors;
    for my $field ( qw[ subject name organization email ] ) {
        my $val = $req->param( $field );
        if ( $val =~ /[\r\n]|(\\[rn])/ ) {
            push @errors, "Field $field '$val' looks like a spam attack."
        }
    }

    my $problem_url    = $req->param('refer_from')   || '';
    my $user_name      = $req->param('name')         || '';
    my $org            = $req->param('organization') || '';
    my $user_email     = $req->param('email')
            or push @errors, 'No email address';
    my $comments       = $req->param('comments')
            or push @errors, 'No comments';
    my $captcha_guess  = $req->param('recaptcha_challenge_field')
            or push @errors, 'Internal CAPTCHA error. Please try again.';
    my $captcha_response = $req->param('recaptcha_response_field')
            or push @errors, 'No text for image';

    if ( $user_email &&
         !Email::Valid->address( -address => $user_email, -mxcheck=> 1 )
    ) {
        push @errors, "Invalid email address '$user_email'";
    }

    # if they guessed something, and it doesn't match, then toss an error
    # if there was no guess, we've already noted that they didn't give us
    # one up above.

    my $captcha_keys = $self->captcha_keys;
    my $captcha      = Captcha::reCAPTCHA->new;
    my $result       = $captcha->check_answer(
        $captcha_keys->{'private'}, 
        $self->req->headers->header('X-Forwarded-For'), # remote IP
        $captcha_guess, 
        $captcha_response
    );

    if ( @errors ) {
        die join("<br>\n", @errors, '');
    }

    my $lx = HTML::LinkExtractor->new;
    $lx->parse( \$comments );
    my $subject = sprintf('Site Feedback: %s', 
        $req->param('subject') || 'No subject',
    );

    my $user         = sprintf '%s%s%s',
        $user_name   ? $user_name : '',
        $org         ? " [$org]"  : '',
        " <$user_email>"
    ;

    my $num_links    = scalar @{ $lx->links };
    my $spamtest     = Mail::SpamAssassin->new;
    my $mail         = $spamtest->parse( $comments );
    my $status       = $spamtest->check( $mail );
    my $is_spam      = $status->is_spam;
    if ( !$is_spam ) {
        if (
               ( $num_links > $MAX_URLS )
            || ( $user_name eq $user_email && $user_email eq $org )
            || ( $subject =~ /@/ )
            || ( $problem_url =~ /@/ )
        ) {
            $is_spam = 1;
        }
    }

    if (length($comments) > $COMMENTS_MAX) {
        $comments = substr($comments, 0, $COMMENTS_MAX);
        $comments .= "\n[MESSAGE TRUNCATED]";
    }

    my $message = join $DOUBLE_NEWLINE,
        "URL         : $problem_url",
        "Subject     : $subject",
        "Name        : $user_name",
        "Email       : $user_email",
        "Organization: $org",
        'Comments    : ',
        $comments,
    ;

    my $tracker = Grm::BugTracker->new;
    my $bug_num;
    eval {
        $bug_num = $tracker->complain(
            summary     => stripaccents($req->param('subject')) || 'NA',
            description => stripaccents($message),
            category    => 'Uncategorized',
        );
    };

    my ( $email_addendum, $user_addendum ) = ( '', '' );
    if ( my $err = $@ ) {
        $email_addendum = "\n\nError creating Mantis ticket:\n\n$err\n";
        $user_addendum  = '';
    }
    elsif ( $bug_num ) {
        $email_addendum = "\n\n$MANTIS_URL$bug_num\n";
        $user_addendum
        = "\n\nYour issue has been assigned the ticket number $bug_num.\n";
    }

    my %mail_args  = (
        'Subject'  => $subject,
        'To'       => $RECIPIENTS,
        'From'     => 'feedback@gramene.org',
        'Cc'       => $user,
        'Reply-To' => "$user_email, $RECIPIENTS",
    );

    sendmail(
        %mail_args,
        'Message' => $message . $email_addendum
    ) or die $Mail::Sendmail::error;

    $self->layout('default');

    $self->render(
        %mail_args,
        'title'      => 'Thank You',
        'return_url' => $problem_url,
        'Message'    => $message . $user_addendum
    );
}

# -------------------------------------------------------

=pod

=head1 NAME

Grm::Web::Feedback - user feedback on Gramene

=head1 DESCRIPTION

Handles user feedback.

=head1 AUTHOR

Ken Youens-Clark E<lt>kclark@cshl.eduE<gt>.

=head1 COPYRIGHT

Copyright (c) 2014 Cold Spring Harbor Laboratory

This library is free software;  you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
