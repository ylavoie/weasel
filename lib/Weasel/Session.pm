
=head1 NAME

Weasel::Session - Connection to an encapsulated test driver

=head1 VERSION

0.03

=head1 SYNOPSIS

  use Weasel;
  use Weasel::Session;
  use Weasel::Driver::Selenium2;

  my $weasel = Weasel->new(
       default_session => 'default',
       sessions => {
          default => Weasel::Session->new(
            driver => Weasel::Driver::Selenium2->new(%opts),
          ),
       });

  $weasel->session->get('http://localhost/index');


=head1 DESCRIPTION



=cut

package Weasel::Session;


use strict;
use warnings;

use Moose;

use Module::Runtime qw/ use_module /;;
use Weasel::FindExpanders qw/ expand_finder_pattern /;
use Weasel::WidgetHandlers qw| best_match_handler_class |;

our $VERSION = '0.03';


=head1 ATTRIBUTES

=over

=item driver

Holds a reference to the sessions's driver.

=cut

has 'driver' => (is => 'ro',
                 required => 1,
                 handles => {
                     'start' => 'start',
                     'stop' => 'stop',
                     'restart' => 'restart',
                     'started' => 'started',
                 });

=item widget_groups

Contains the list of widget groups to be used with the session, or
uses all groups when undefined.

Note: this functionality allows to load multiple groups into the running
perl instance, while using different groups in various sessions.

=cut

has 'widget_groups' => (is => 'rw');

=item base_url

Holds the prefix that will be prepended to every URL passed
to this API.
The prefix can be an environment variable, e.g. ${VARIABLE}.
It will be expanded and default to hppt://localhost:5000 if not defined.
If it is not an environment variable, it will be used as is.

=cut

has 'base_url' => (is => 'rw',
                   isa => 'Str',
                   default => '' );

=item page

Holds the root element of the target HTML page (the 'html' tag).

=cut

has 'page' => (is => 'ro',
               isa => 'Weasel::Element::Document',
               builder => '_page_builder',
               lazy => 1);

sub _page_builder {
    my $self = shift;
    my $class = use_module($self->page_class);

    return $class->new(session => $self);
}

=item log_hook

Upon instantiation can be set to log consumer; a function of 3 arguments:
 1. the name of the event
 2. the text to be logged (or a coderef to be called without arguments returning such)

=cut

has 'log_hook' => (is => 'ro',
                   isa => 'Maybe[CodeRef]');

=item page_class

Upon instantiation can be set to an alternative class name for the C<page>
attribute.

=cut

has 'page_class' => (is => 'ro',
                     isa => 'Str',
                     default => 'Weasel::Element::Document');

=item retry_timeout

The number of seconds to poll for a condition to become true. Global
setting for the C<wait_for> function.

=cut

has 'retry_timeout' => (is => 'rw',
                        default => 15,
                        isa => 'Num',
    );

=item poll_delay

The number of seconds to wait between state polling attempts. Global
setting for the C<wait_for> function.

=cut

has 'poll_delay' => (is => 'rw',
                     default => 0.5,
                     isa => 'Num',
    );

=back

=head1 METHODS


=over

=item clear($element)

Clears any input entered into elements supporting it.  Generally applies to
textarea elements and input elements of type text and password.

=cut

sub clear {
    my ($self, $element) = @_;

    $self->_logged(sub { $self->driver->clear($element->_id); },
                   'clear', 'clearing input element');
}

=item click([$element])

Simulates a single mouse click. If an element argument is provided, that
element is clicked.  Otherwise, the browser window is clicked at the
current mouse location.

=cut

sub click {
    my ($self, $element) = @_;

    $self->_logged(
        sub {
            $self->driver->click(($element) ? $element->_id : undef);
        },
        'click', ($element) ? 'clicking element' : 'clicking window');
}

=item find($element, $locator [, scheme => $scheme] [, %locator_args])

Finds the first child of C<$element> matching C<$locator>.

See L<Weasel::Element>'s C<find> function for more documentation.

=cut

sub find {
    my ($self, @args) = @_;
    my $rv;

    $self->_logged(
        sub {
            $self->wait_for(
                sub {
                    my @rv = @{$self->find_all(@args)};
                    return $rv = shift @rv;
                });
        }, 'find', 'find ' . $args[1]);

    return $rv;
}

=item find_all($element, $locator, [, scheme => $scheme] [, %locator_args ])

Finds all child elements of C<$element> matching C<$locator>. Returns,
depending on scalar or list context, an arrayref or a list with matching
elements.

See L<Weasel::Element>'s C<find_all> function for more documentation.

=cut

sub find_all {
    my ($self, $element, $pattern, %args) = @_;

    my $expanded_pattern = expand_finder_pattern($pattern, \%args);
    my @rv = $self->_logged(
        sub {
            return
                map { $self->_wrap_widget($_) }
                $self->driver->find_all($element->_id,
                                        $expanded_pattern,
                                        $args{scheme});
        },
        'find_all',
        sub {
            my ($rv) = @_;
            return "found " . scalar(@$rv) . " elements for $pattern "
                . (join(', ', %args)) . "\n"
                . (join("\n",
                        map { ' - ' . ref($_)
                                  . ' (' . $_->tag_name . ")" } @$rv));
        },
        "pattern: $pattern");
    return wantarray ? @rv : \@rv;
}


=item get($url)

Loads C<$url> into the active browser window of the driver connection,
after prefixing with C<base_url>.

=cut

sub get {
    my ($self, $url) = @_;

    my $base = $self->base_url =~ /\$\{([a-zA-Z0-9_]+)\}/
             ? $ENV{$1} // "http://localhost:5000"
             : $self->base_url;

    $url = $base . $url;
    ###TODO add logging warning of urls without protocol part
    # which might indicate empty 'base_url' where one is assumed to be set
    $self->_logged(
        sub {
            return $self->driver->get($url);
        }, 'get', "loading URL: $url");
}

=item get_attribute($element, $attribute)

Returns the value of the attribute named by C<$attribute> of the element
identified by C<$element>, or C<undef> if the attribute isn't defined.

=cut

sub get_attribute {
    my ($self, $element, $attribute) = @_;

    return $self->_logged(
        sub {
            return $self->driver->get_attribute($element->_id, $attribute);
        }, 'get_attribute', "element attribute '$attribute'");
}

=item get_text($element)

Returns the 'innerHTML' of the element identified by C<$element>.

=cut

sub get_text {
    my ($self, $element) = @_;

    return $self->_logged(
        sub {
            return $self->driver->get_text($element->_id);
        },
        'get_text', 'element text');
}

=item is_displayed($element)

Returns a boolean value indicating if the element identified by
C<$element> is visible on the page, i.e. that it can be scrolled into
the viewport for interaction.

=cut

sub is_displayed {
    my ($self, $element) = @_;

    return $self->_logged(
        sub {
            return $self->driver->is_displayed($element->_id);
        },
        'is_displayed', 'query is_displayed');
}

=item screenshot($fh)

Writes a screenshot of the browser's window to the filehandle C<$fh>.

Note: this version assumes pictures of type PNG will be written;
  later versions may provide a means to query the exact image type of
  screenshots being generated.

=cut

sub screenshot {
    my ($self, $fh) = @_;

    $self->_logged(
        sub {
            $self->driver->screenshot($fh);
        }, 'screenshot', 'screenshot');
}

=item get_page_source($fh)

Writes a get_page_source of the browser's window to the filehandle C<$fh>.

=cut

sub get_page_source {
    my ($self) = @_;

    $self->_logged(
        sub {
            $self->driver->get_page_source();
        }, 'get_page_source', 'get_page_source');
}

=item send_keys($element, @keys)

Send the characters specified in the strings in C<@keys> to C<$element>,
simulating keyboard input.

=cut

sub send_keys {
    my ($self, $element, @keys) = @_;

    $self->_logged(
        sub {
            $self->driver->send_keys($element->_id, @keys);
        },
        'send_keys', 'sending keys: ' . join('', @keys // ()));
}

=item alert_is_present

Checks if there is a javascript alert/confirm/input on the screen.
Returns alert text if so.

=cut

sub alert_is_present {
    my ($self) = @_;

    $self->_logged(
        sub {
            $self->driver->alert_is_present;
        },
        'alert_is_present');
}

=item accept_alert

Accepts the currently displayed alert dialog.  Usually, this is
equivalent to clicking the 'OK' button in the dialog.

=cut

sub accept_alert {
    my ($self) = @_;

    $self->_logged(
        sub {
            $self->driver->accept_alert;
        },
        'accept_alert');
}

=item dismiss_alert

Dismisses the currently displayed alert dialog. For comfirm()
and prompt() dialogs, this is equivalent to clicking the
'Cancel' button. For alert() dialogs, this is equivalent to
clicking the 'OK' button.

=cut

sub dismiss_alert {
    my ($self) = @_;

    $self->_logged(
        sub {
            $self->driver->dismiss_alert;
        },
        'dismiss_alert');
}

=item tag_name($element)

Returns the tag name of the element identified by C<$element>.

=cut

sub tag_name {
    my ($self, $element) = @_;

    return $self->_logged(sub { return $self->driver->tag_name($element->_id) },
         'tag_name',
         sub { my $tag = shift; return "found tag with name $tag" },
         'getting tag name');
}

=item wait_for($callback, [ retry_timeout => $number,] [poll_delay => $number])

Polls $callback->() until it returns true, or C<wait_timeout> expires
-- whichever comes first.

The arguments retry_timeout and poll_delay can be used to override the
session-global settings.

=cut

sub wait_for {
    my ($self, $callback, %args) = @_;

    $self->_logged(
        sub {
            $self->driver->wait_for($callback,
                                    retry_timeout => $self->retry_timeout,
                                    poll_delay => $self->poll_delay,
                                    %args);
        },
        'wait_for', 'waiting for condition');
}


before 'BUILDARGS', sub {
    my ($class, @args) = @_;
    my $args = (ref $args[0]) ? $args[0] : { @args };

    confess "Driver used to construct session object uses old API version;
some functionality may not work correctly"
        if ($args->{driver}
            && $args->{driver}->implements < $Weasel::DriverRole::VERSION);
};

sub _appending_wrap {
    my ($str) = @_;
    return sub {
        my $rv = shift;
        if ($rv) {
            return "$str ($rv)";
        }
        else {
            return $str;
        }
    }
}

=item _logged($wrapped_fn, $event, $log_item, $log_item_pre)

Invokes C<log_hook> when it's defined, before and after calling C<$wrapped_fn>
with no arguments, with the 'pre_' and 'post_' prefixes to the event name.

C<$log_item> can be a fixed string or a function of one argument returning
the string to be logged. The argument passed into the function is the value
returned by the C<$wrapped_fn>.

In case there is no C<$log_item_pre> to be called on the 'pre_' event,
C<$log_item> will be used instead, with no arguments.

For performance reasons, the C<$log_item> and C<$log_item_pre> - when
coderefs - aren't called; instead they are passed as-is to the
C<$log_hook> for lazy evaluation.

=cut

sub _logged {
    my ($self, $f, $e, $l, $lp) = @_;
    my $hook = $self->log_hook;

    return $f->() if ! defined $hook;

    $lp //= $l;
    my $pre = (ref $lp eq 'CODE') ? $lp : _appending_wrap($lp);
    my $post = (ref $l eq 'CODE') ? $l : _appending_wrap($l);
    $hook->("pre_$e", $pre);
    if (wantarray) {
        my @rv = $f->();
        $hook->("post_$e", sub { return $l->(\@rv); });
        return @rv;
    }
    else {
        my $rv = $f->();
        $hook->("post_$e", sub { return $l->($rv); });
        return $rv;
    }
};

=item _wrap_widget($_id)

Finds all matching widget selectors to wrap the driver element in.

In case of multiple matches, selects the most specific match
(the one with the highest number of requirements).

=cut

sub _wrap_widget {
    my ($self, $_id) = @_;
    my $best_class = best_match_handler_class(
        $self->driver, $_id, $self->widget_groups) // 'Weasel::Element';
    return $best_class->new(_id => $_id, session => $self);
}

=back

=head1 SEE ALSO

L<Weasel>

=head1 COPYRIGHT

 (C) 2016  Erik Huelsmann

Licensed under the same terms as Perl.

=cut


1;
