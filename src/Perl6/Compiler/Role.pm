class Perl6::Compiler::Role is Perl6::Compiler::Package;

# Holds the signautre for this parametric role, if any.
has $!signature;

# Accessor for signature.
method signature($signature?) {
    if pir::defined__IP($signature) { $!signature := $signature }
    $!signature
}

# Do the code generation for the parametric role.
method finish($block) {
    my $decl := PAST::Stmts.new();

    # Sanity check on scoping.
    if self.scope eq 'augment' || self.scope eq 'supercede' {
        pir::die('A role is immutable and may not be modified');
    }

    # Create meta-class RoleHOW, which will hold details of this particular
    # role variant.
    my $how := self.how;
    my @how := Perl6::Grammar::parse_name(~$how);
    my $metaclass := PAST::Var.new( :name(@how.pop), :namespace(@how), :scope('package') );
    my $meta_reg := PAST::Var.new( :name('meta'), :scope('register') );
    my $name := $!name ?? ~$!name !! '';
    $decl.push(PAST::Op.new(
        :pasttype('bind'),
        PAST::Var.new( :name('meta'), :scope('register'), :isdecl(1) ),
        PAST::Op.new(
            :pasttype('callmethod'),
            :name('new'),
            $metaclass,
            $name
        )
    ));

    # Methods.
    my %methods := self.methods;
    for %methods {
        $decl.push(PAST::Op.new(
            :pasttype('callmethod'),
            :name('add_method'),
            $metaclass, $meta_reg, ~$_, %methods{~$_}<code_ref>
        ));
    }

    # Attributes.
    my %attrs := self.attributes;
    for %attrs {
        $decl.push(PAST::Op.new(
            :pasttype('callmethod'),
            :name('add_attribute'),
            $metaclass, $meta_reg, ~$_
        ));
    }

    # Traits.
    if self.traits {
        for @(self.traits) {
            $_.unshift($meta_reg);
            $decl.push($_);
        }
    }

    # Call compose to create the role object.
    $decl.push(PAST::Op.new( :pasttype('callmethod'), :name('compose'), $metaclass, $meta_reg ));

    # We need the block to get the signature, or a default one, plus the
    # decl code as a body.
    my $sig := pir::defined__IP($!signature) ?? $!signature !! Perl6::Compiler::Signature.new();
    Perl6::Actions::add_signature($block, $sig);
    $block.push($decl);
    $block.blocktype('declaration');
    $block.nsentry('');

    # Unless the role is anonymous, in the loadinit we need to have code
    # to add this role variant to the main role object that goes in the
    # namespace or lexpad.
    if $name {
        my @name := Perl6::Grammar::parse_name($name);
        my $short_name := @name.pop;
        $block.loadinit.push(PAST::Op.new( :pasttype('bind'),
            PAST::Var.new( :name('master_role'), :scope('register'), :isdecl(1) ),
            PAST::Var.new(
                :name($short_name), :namespace(@name), :scope('package'),
                :viviself(PAST::Op.new( :pasttype('call'), :name('!create_master_role'), ~$short_name ))
            )
         ));
        $block.loadinit.push(PAST::Op.new(
            :pasttype('callmethod'), :name('!add_variant'),
            PAST::Var.new( :name('master_role'), :scope('register') ),
            Perl6::Actions::create_code_object(PAST::Var.new( :name('block'), :scope('register') ), 'Sub', 1)
        ));
        $block.loadinit.push(PAST::Op.new( :pasttype('bind'),
            PAST::Var.new( :name($short_name), :namespace(@name), :scope('package') ),
            PAST::Var.new( :name('master_role'), :scope('register') )
        ));
    }

    # Otherwise, for anonymous, make such an object and hand it back.
    else {
        $block := PAST::Stmts.new(
            PAST::Op.new( :pasttype('bind'),
                PAST::Var.new( :name('tmp_role'), :scope('register'), :isdecl(1) ),
                PAST::Op.new( :pasttype('call'), :name('!create_master_role'), '')
            ),
            PAST::Op.new( :pasttype('callmethod'), :name('!add_variant'),
                PAST::Var.new( :name('tmp_role'), :scope('register') ),
                $block
            ),
            PAST::Var.new( :name('tmp_role'), :scope('register') )
        );
    }

    return $block;
}