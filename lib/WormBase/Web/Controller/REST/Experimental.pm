package WormBase::Web::Controller::REST::Experimental;

use strict;
use warnings;
use parent 'Catalyst::Controller::REST';

use namespace::autoclean -except => 'meta';

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => {
        'text/html'        => 'YAML::HTML',
        'text/xml'         => 'XML::Simple',
        'application/json' => 'JSON',
    },
);

sub phenotype_rnai :Path('phenotype/rnai') :ActionClass('REST') {}

sub phenotype_rnai_GET :Args(1) {
    my ($self, $c, $id) = @_;

    $c->log->debug("PHENOTYPE ID IS: $id");

    my $phen = $c->model('WormBaseAPI')->fetch({
        class => 'Phenotype',
        name  => $id,
    });

    my ($result, $total) = 
        $phen->experimental_rnai(@{$c->req->params}{qw(iDisplayStart iDisplayLength)});

    $c->stash->{rest} = {
        iTotalRecords        => $total,
        iTotalDisplayRecords => $total,
        sEcho                => $c->req->params->{sEcho},
        aaData               => $result,
    };
}

__PACKAGE__->meta->make_immutable;

1;
