## OpenXPKI::Exception
##
## Written by Michael Bell for the OpenXPKI project
## Copyright (C) 2005 by The OpenXPKI Project

package OpenXPKI::Exception;

use strict;
use warnings;
use utf8;

use OpenXPKI::Debug;
use OpenXPKI::Server::Context;
use Log::Log4perl qw( get_logger );

use OpenXPKI::i18n qw( i18nGettext );
use Exception::Class (
    "OpenXPKI::Exception" => {
        fields => [ "children", "params" ],
    }
);

my $log4perl_logger;

sub full_message {
    my ($self) = @_;

    ## respect child errors
    if (ref $self->{children}) {
        foreach my $child (@{$self->{children}}) {
            next if (not $child); ## empty array
            $self->{params}->{"ERRVAL"} .= " " if ($self->{params}->{"ERRVAL"});
            if (ref $child) {
                $self->{params}->{"ERRVAL"} .= $child->as_string();
            }
            else {
                $self->{params}->{"ERRVAL"} = $self->{child};
            }
        }
    }

    ## enforce __NAME__ scheme
    foreach my $param (sort keys %{$self->{params}}) {
        my $value = $self->{params}->{$param};
        delete $self->{params}->{$param};
        $param =~s/^_*/__/;
        $param =~s/_*$/__/;
        $self->{params}->{$param} = $value;
    }

    ## put together and translate message
    my $msg = OpenXPKI::i18n::i18nGettext ($self->{message}, %{$self->{params}});
    if ($msg eq $self->{message}) {
        # the message was not translated
        if (scalar keys %{$self->{params}}) {
            # normalize the output => sort keys
            # otherwise the output is not predictable
            foreach my $key (sort keys %{$self->{params}}) {
                $msg = $msg.", ".$key." => ".$self->{params}->{$key};
            }
        }
    }
    ## this is only for debugging of OpenXPKI::Exception
    ## and creates a lot of noise
    ## print STDERR "$msg\n";

    ##! 1: "exception thrown: $msg"

    return $msg;
}

sub message_code {
    my $self = shift;
    return $self->{message};
}

sub throw {
    my $proto = shift;

    $proto->rethrow if ref $proto;

    my %args           = (@_);
    my %exception_args = %args;
    delete $exception_args{log};

    #    # This is a bit of an evil hack until Exception::Class supports
    #    # turning off stack traces, see
    #    # http://rt.cpan.org/Ticket/Display.html?id=26489
    #    # for a bug report and patch
    #    # It fakes the Devel::StackTrace calls that are used in
    #    # Exception::Class to be nearly empty, which massively speeds up
    #    # Exception throwing
    #    local *Devel::StackTrace::new
    #        = *OpenXPKI::Exception::__fake_stacktrace_new;
    #    local *Devel::StackTrace::frame
    #        = *OpenXPKI::Exception::__fake_stacktrace_frame;

    my $self = $proto->new(%exception_args);

    my %logger_args = (
        MESSAGE     => 'Exception: ' . $self->full_message(%args),
        FACILITY    => 'system',
        PRIORITY    => 'error',
        CALLERLEVEL => 1,
    );

    # exceptions get logged by default if no "log" given
    unless (exists $args{log}) {
        __log(%logger_args);
        die $self;
    }
    # suppress logging if "log => undef"
    unless (defined $args{log}) {
        die $self;
    }

    $logger_args{MESSAGE}  = $args{log}->{message}  if exists $args{log}->{message};
    $logger_args{FACILITY} = $args{log}->{facility} if exists $args{log}->{facility};
    $logger_args{PRIORITY} = $args{log}->{priority} if exists $args{log}->{priority};

    # logger object was explicitly specified
    if ( exists $args{log}->{logger}
        and ( ref $args{log}->{logger} eq 'OpenXPKI::Server::Log' ) ) {
        $args{log}->{logger}->log(%logger_args);
        delete $args{log};
    }
    # standard logging
    else {
        __log(%logger_args);
    }

    die $self;
}

sub __log {
    my %logger_args = ( @_ );

    my $logger;
    eval {
        $logger = OpenXPKI::Server::Context::CTX('log');
    };

    if (defined $logger) {
        # we have an OpenXPKI logger available
        $logger->log(%logger_args);
    }
    else {
        # no system logger found, falling back to Log4perl
        $log4perl_logger ||= get_logger('openxpki.system');
        $log4perl_logger->debug($logger_args{MESSAGE});
    }
}

sub __fake_stacktrace_new {
    ##! 16: 'fake_stacktrace_new called'
    my $that  = shift;
    my $class = ref($that) || $that;

    my $self = {};
    bless $self, $class;

    return $self;
}

sub __fake_stacktrace_frame {
    ##! 16: 'fake_stacktrace_frame called'
    return 0;
}

1;
__END__

=head1 Name

OpenXPKI::Exception - central exception class of OpenXPKI.

=head1 Description

This is the basic exception class of OpenXPKI.

=head1 Intended use

OpenXPKI::Exception->throw (message => "I18N_OPENXPKI_FAILED",
                            children  => [$other_exception],#opt.
                            params  => {FILENAME => $file});

if (my $exc = OpenXPKI::Exception->caught())
{
    ## handle it or throw again
    my $errno  = $exc->errno();
    my $errval = $exc->as_string();
    OpenXPKI::Exception->throw (message => ..., child => $exc, params => {...});
} else {
    $EVAL_ERROR->rethrow();
}

Please note that FILENAME will be extended to __FILENAME__. If you want
to send a specific errorcode to the caller then you can specify errno
directly like message, child or params.

=head1 New Functions

usually all functions from Exception::Class will be used. Nevertheless
one function will be overloaded and on new function will be specified
to support other modules with errorcodes if one is available.

=head2 full_message

This function is used to build the new errormessages conforming to
the specifications of OpenXPKI. This means in the first line the
specification of i18n.

=head2 message_code

returns the untranslated and unmodified i18n-message-code

=head2 Fields

returns the names of the available parameters (message, errno, child, params).

=head2 errno

errno returns the errorcode if available.

=head2 child

returns the exception object of the child if this is
a nested exception.

=head2 params

returns a hash reference with name and value pairs of the parameters for
the error message (i18nGettext).
