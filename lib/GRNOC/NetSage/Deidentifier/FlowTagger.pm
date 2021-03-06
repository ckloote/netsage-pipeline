package GRNOC::NetSage::Deidentifier::FlowTagger;

use strict;
use warnings;

use Moo;
extends 'GRNOC::NetSage::Deidentifier::Pipeline';
use Socket;
use Socket6;
use Geo::IP;
use Data::Validate::IP;
use Text::Unidecode; # TODO: REMOVE THIS once TSDS bug is fixed
use Encode;
use Net::IP;

use GRNOC::Log;
use GRNOC::Config;

use Data::Dumper;


### internal attributes ###

has handler => ( is => 'rwp');


has geoip_country => ( is => 'rwp' );
has geoip_country_ipv6 => ( is => 'rwp' );

has geoip_city => ( is => 'rwp' );
has geoip_city_ipv6 => ( is => 'rwp' );

has geoip_asn => ( is => 'rwp' );
has geoip_asn_ipv6 => ( is => 'rwp' );

my %continents = (
    'AF' => 'Africa',
    'AS' => 'Asia',
    'EU' => 'Europe',
    'NA' => 'North America',
    'OC' => 'Oceania',
    'SA' => 'South Africa'
);

### constructor builder ###

sub BUILD {

    my ( $self ) = @_;

    my $config = $self->config;
    $self->_set_handler( sub { $self->_tag_messages(@_) } );

    #my $geoip_country_ipv6_file = $config->get( '/config/geoip/config_files/country_ipv6' );
    my $geoip_country_ipv6_file = $config->{ 'geoip'}->{'config_files'}->{'country_ipv6'};
    my $geoip_country_ipv6 = Geo::IP->open( $geoip_country_ipv6_file, GEOIP_MEMORY_CACHE);
    $self->_set_geoip_country_ipv6( $geoip_country_ipv6 );

        my $geoip_asn_file = $config->{'geoip'}->{'config_files'}->{'asn'};
        my $geoip_asn = Geo::IP->open( $geoip_asn_file, GEOIP_MEMORY_CACHE);
        $self->_set_geoip_asn( $geoip_asn );

    my $geoip_asn_ipv6_file = $config->{'geoip'}->{'config_files'}->{'asn_ipv6'};
    my $geoip_asn_ipv6 = Geo::IP->open( $geoip_asn_ipv6_file, GEOIP_MEMORY_CACHE);
    $self->_set_geoip_asn_ipv6( $geoip_asn_ipv6 );

    my $geoip_city_ipv6_file = $config->{'geoip'}->{'config_files'}->{'city_ipv6'};
    my $geoip_city_ipv6 = Geo::IP->open( $geoip_city_ipv6_file, GEOIP_MEMORY_CACHE);
    $self->_set_geoip_city_ipv6( $geoip_city_ipv6 );

    my $geoip_city_file = $config->{ 'geoip'}->{'config_files'}->{'city'};
    my $geoip_city = Geo::IP->open( $geoip_city_file, GEOIP_MEMORY_CACHE);
    $self->_set_geoip_city( $geoip_city );


    return $self;
}

### private methods ###

# expects an array of data for it to tag
# returns the tagged array
sub _tag_messages {
    my ( $self, $caller, $messages ) = @_;
    #my $geoip_country = $self->geoip_country; # we're using city for country also
    my $geoip_city = $self->geoip_city;
    my $geoip_city_ipv6 = $self->geoip_city_ipv6;
    my $geoip_country_ipv6 = $self->geoip_country_ipv6;
    my $geoip_asn = $self->geoip_asn;
    my $geoip_asn_ipv6 = $self->geoip_asn_ipv6;

    my $finished_messages = $messages;

    foreach my $message ( @$messages ) {
        my @fields = ( 'src_ip', 'dst_ip');
        foreach my $field ( @fields ) {
            my $field_direction = $field;
            $field_direction =~ s/_ip//g;
            my $ip = $message->{'meta'}->{ $field };
            my %metadata = ();
            $metadata{'country_code'} = undef;
            $metadata{'country_name'} = undef;
            $metadata{'city'} = undef;
            $metadata{'region'} = undef;
            $metadata{'region_name'} = undef;
            $metadata{'postal_code'} = undef;
            $metadata{'time_zone'} = undef;
            $metadata{'latitude'} = undef;
            $metadata{'longitude'} = undef;
            $metadata{'asn'} = undef;
            $metadata{'organization'} = undef;

            my $asn_org;
            $message->{'type'} = 'flow'; # TODO: remove. temporary until the data pushed has this field


            if ( is_ipv4( $ip ) ) {
                my $record;
                my ( $country_code, $country_name, $city, $latitude, $longitude );

                $asn_org = $geoip_asn->org_by_addr( $ip );


                $record = $geoip_city->record_by_addr( $ip );


                if ( $record ) {
                    $metadata{'country_code'} = $self->convert_chars( $record->country_code );
                    $metadata{'country_name'} = $self->convert_chars( $record->country_name );
                    $metadata{'city'} = $self->convert_chars( $record->city );
                    $metadata{'region'} = $self->convert_chars( $record->region );
                    $metadata{'region_name'} = $self->convert_chars( $record->region_name );
                    $metadata{'postal_code'} = $self->convert_chars( $record->postal_code );
                    $metadata{'time_zone'} = $record->time_zone;
                    $metadata{'latitude'} = $record->latitude;
                    $metadata{'longitude'} = $record->longitude;
                    $metadata{'continent_code'} = $record->continent_code;
                    $metadata{'continent'} = $self->get_continent( $record->continent_code );

                    }
            } elsif ( is_ipv6( $ip ) )  {
                # TODO: extend to ipv6

                my $record;
                $record = $geoip_city_ipv6->record_by_addr_v6( $ip );

                $asn_org =  $geoip_asn_ipv6->name_by_addr_v6 ( $ip );

                if ( $record ) {
                    # NOTE: some of these don't seem to work for ipv6:
                    # city, region/region_name, postal_code, time_zone
                    $metadata{'country_code'} = $self->convert_chars($record->country_code);
                    $metadata{'country_name'} = $self->convert_chars($record->country_name);
                    $metadata{'city'} = $self->convert_chars($record->city);
                    $metadata{'region'} = $self->convert_chars($record->region);
                    $metadata{'region_name'} = $self->convert_chars($record->region_name);
                    $metadata{'postal_code'} = $self->convert_chars($record->postal_code);
                    $metadata{'time_zone'} = $record->time_zone;
                    $metadata{'latitude'} = $record->latitude;
                    $metadata{'longitude'} = $record->longitude;
                    $metadata{'continent_code'} = $record->continent_code;
                    $metadata{'continent'} = $self->get_continent( $record->continent_code );

                }
                #warn "metadata IPV6: " . Dumper \%metadata;




            } else {
                # not detected as ipv4 nor ipv6
                warn "\n\nNOTICE: address not detected as ipv4 or ipv6: $ip\n\n";
                $self->logger->warn( "NOTICE: address not detected as ipv4 or ipv6: $ip"  );
                # TODO: handle failure better

            }
                if ( $asn_org ) {
                    if ( $asn_org =~ /^AS(\d+)\s+(.+)$/ ) {
                        my $asn = $1;
                        my $organization = $2;
                        $metadata{'asn'} = $asn;
                        $metadata{'organization'} = $self->convert_chars( $organization );

                    } else {
                        #warn "\n\nASN/ORG don't match regex\n\n";
                    }
                } else {
                    #warn "ASN NOT DEFINED";
                }

                # look for null values and change to '';
                foreach my $key ( keys %metadata ) {
                    my $val = $metadata{ $key };
                    if ( not defined $val ) {
                        $val = '';
                        $metadata{ $key } = $val;
                    }
                }

            # for now, we're going to tag these:
            # ASN
            # Country Code
            # Country Name
            # Latitude
            # Longitude
            my @meta_names = ( 'asn', 'city', 'country_code', 'country_name',
                'latitude', 'longitude', 'organization', 'continent_code', 'continent');
            foreach my $name ( @meta_names ) {
                $message->{'meta'}->{ $field_direction ."_" . $name } = $metadata{ $name }; # if $metadata{ $name };
            }
            #warn "message: " . Dumper ( $message ) if $metadata{'city'} =~ /^Mont/;

        }

    }

    return $finished_messages;
}

sub get_continent {
    my ( $self, $abbr ) = @_;
    my $continent = $continents{ $abbr };

    return $continent;
}

sub convert_chars {
    my ( $self, $input ) = @_;
    $input = unidecode( $input ); # TODO: REMOVE THIS once TSDS bug is fixed
    return $input;
}

1;
