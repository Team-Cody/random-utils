#!/usr/bin/perl -w
#
# Author: Radim Gelner <radim.gelner@suse.cz>
# Copyright (c) 2001, SuSE CR
#
# for more information type 'man xdeltadir'

package main;

sub pathname {
  local ( $path, $offset ) = @_;

  if ( !( $offset ) ) {
    return $path;
  }
  if ( !( $path ) ) {
    return $offset;
  }
  return $path.'/'.$offset;
}

sub log_entry {
  local ( $entry, $flags ) = @_;

  if ( $flags & $log_flag ) {
    print ( LOG $entry."\n" );
  }
  if ( ( ( $flags & $debug_flag ) && $debug_set ) || ( $flags & $verbose_flag ) ) {
    print ( $entry."\n" );
  }
}

sub copy_attributes {
  local ( $name_1, $name_2 ) = @_;

  local $dev;
  local $ino;
  local $mode;
  local $nlink;
  local $uid;
  local $gid;
  local $rdev;
  local $size;
  local $atime;
  local $mtime;
  local $ctime;
  local $blksize;
  local $blocks;
  local ( *FILE );

  open ( FILE, $name_1 ) || die ( "Error: can not open file ".$name_1 );
  ( $dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks ) = stat ( "$name_1" );
  close ( FILE );
  log_entry ( "Copying permissions and ownership of ".$name_1." to ".$name_2, $debug_flag );
  chmod $mode, $name_2;
  chown $uid, $gid, $name_2;
}

sub xdelta_call {
  local ( $delta_flag, $from, $to, $patch ) = @_;
  local $returncode;
  local $command;
  local $parameters;

  if ( $delta_flag ) {
    $command = "delta";
    $parameters = "-9 \'$from\' \'$to\' \'$patch\'";
  }
  else {
    $command = "patch";
    $parameters = "\'$to\' \'$from\' \'$patch\'";
  }

  log_entry ( "Performing \'xdelta ".$command." ".$parameters."\'", $debug_flag );

  $returncode = system ( "xdelta ".$command." ".$parameters );
  if ( ( $returncode != 0 ) && ( $returncode != 256 ) ) {
     die ( "Error: calling \'xdelta ".$command." ".$parameters."\'" );
  }
}

sub process_file {
  local ( $base_1, $base_2, $base_new, $name, $delta ) = @_;
  local ( *FILE );
  local $returncode;
  local $link;

  if ( -l pathname ( $base_1, $name ) ) {
    $link = readlink ( pathname ( $base_1, $name ) );
    symlink ( $link, pathname ( $base_new, $name ) ) || die ( "Error: can not create symlink ".pathname ( $base_new, $name )." pointing to ".$link );
    return ();
  }

  if ( -d pathname ( $base_1, $name ) ) {
    log_entry ( "Creating directory ".pathname ( $base_new, $name ), $debug_flag );
    mkdir ( pathname ( $base_new, $name ), 0755 ) || die ( "Error: can not create directory ".pathname ( $base_new, $name ));
    copy_attributes ( pathname ( $base_1, $name ), pathname ( $base_new, $name ) );
    if ( ! ( -e pathname ( $base_2, $name ) ) ) {
      log_entry ( "Creating directory ".pathname ( $base_2, $name), $debug_flag );
      mkdir ( pathname ( $base_2, $name ), 0755 ) || die ( "Error: can not create directory ".pathname ( $base_2, $name ));
      log_entry ( pathname ( $base_2, $name ), $log_flag );
    }
  }
  else {
    if ( ! ( -e pathname ( $base_2, $name ) ) ) {
      log_entry ( "File ".pathname ( $base_2, $name )." does not exists. Creating an empty file instead.", $debug_flag );
      open ( FILE, ">".pathname ( $base_2, $name ) ) || die ( "Error: can not create file ".pathname ( $base_2, $name ) );
      close ( FILE );
      log_entry ( pathname ( $base_2, $name ), $log_flag );
      xdelta_call ( $delta, pathname ( $base_2, $name ), pathname ( $base_1, $name ), pathname ( $base_new, $name ) );
      copy_attributes ( pathname ( $base_1, $name ), pathname ( $base_new, $name ) );
    }
    else {
      xdelta_call ( $delta, pathname ( $base_2, $name ), pathname ( $base_1, $name ), pathname ( $base_new, $name ) );
      copy_attributes ( pathname ( $base_1, $name ), pathname ( $base_new, $name ) );
    }
  }
}

sub process_directory {
  local ( $base_1, $base_2, $base_new, $offset, $delta ) = @_;
  local $name_l2;
  local( *CURDIRDESC );

  if ( ! -d pathname ( $base_1, $offset ) ) {
    die ( "Error: $base_1.'/'.$offset is not a directory!" );
  }

  if ( -l pathname ( $base_1, $offset ) ) {
    return ();
  }

  log_entry ( "Entering directory ".pathname ( $base_1, $offset), $debug_flag+$verbose_flag );

  opendir (CURDIRDESC, pathname ( $base_1, $offset ) );
  while ( $name_l2 = readdir (CURDIRDESC) ) {
    if ( !( $name_l2 eq "." || $name_l2 eq ".."  ) ) {
      if ( -d pathname ( pathname ( $base_1, $offset), $name_l2 ) ) {
        process_file ( $base_1, $base_2, $base_new, pathname ( $offset, $name_l2 ), $delta );
        process_directory ( $base_1, $base_2, $base_new, pathname ( $offset, $name_l2 ), $delta );
      }
      else {
        log_entry ( "File ".pathname ( pathname ( $base_1, $offset), $name_l2 ), $debug_flag );
        process_file ( $base_1, $base_2, $base_new, pathname ( $offset, $name_l2 ), $delta );
      }
    }
  }
  closedir ( CURDIRDESC );
  log_entry ( "Leaving directory ".pathname ( $base_1, $offset ), $debug_flag+$verbose_flag );
}

sub clean_temp {
  local ( $processdir ) = @_;

  while ( $entry = <LOG> ) {
    if ( !( $entry =~ /^\s*#/ ) ) {
      chomp ( $entry );
      if ( -e $entry ) {
        if ( $processdir ) {
          if ( -d $entry ) {
            rmdir ( $entry ) || warn ( "Warning: can not remove directory $entry" );
          }
        }
        else {
          if ( !( -d $entry ) ) {
            unlink ( $entry ) || warn ( "Warning: can not remove file $entry" );
          }
        }
      }
      else {
        log_entry ( $entry." does not exist", $debug_flag );
      }
    }
  }
}

sub help {

  log_entry ( "\nUsage:\n\n".
              "  xdeltadir.pl delta from_dir to_dir patch_dir\n\n".
              "    from_dir  - directory containig original versions of the files\n".
              "    to_dir    - directory containing final versions of the files\n".
              "    patch_dir - directory, in which the deltas will be created\n\n".
              "  xdeltadir.pl patch patch_dir from_dir to_dir\n\n".
              "    patch_dir - directory, containing the deltas\n".
              "    from_dir  - directory containig original versions of the files\n".
              "    to_dir    - directory, in which the final versions will be created\n\n".
              "  Note: All the directories must exist.\n", $debug_flag+$verbose_flag );
  exit ();
}

$log_flag     = 1;
$debug_flag   = 2;
$verbose_flag = 4;

$debug_set    = 0;

if ($#ARGV<3) {
    help ();
}

if ( ( $ARGV [ 0 ] ne "delta" ) && ( $ARGV [ 0 ] ne "patch" ) ) {
  help ();
}

if ( $ARGV [ 0 ] eq "delta" ) {
  $base_1 = $ARGV [ 2 ];
  $base_2 = $ARGV [ 1 ];
  $base_new = $ARGV [ 3 ];
  $delta = 1;
}
else {
  $base_1 = $ARGV [ 1 ];
  $base_2 = $ARGV [ 2 ];
  $base_new = $ARGV [ 3 ];
  $delta = 0;
}

log_entry ( "### Phase I - traversing $base_1", $debug_flag+$verbose_flag );

open ( LOG, ">xdeltadir.log" ) || die ( "Error: can not create file xdeltadir.log" );
log_entry ( "# Files and directories temporarily created in $base_2", $log_flag );

process_directory ( $base_1, $base_2, $base_new, "", $delta );

close ( LOG );

log_entry ( "Completed succesfully.", $debug_flag+$verbose_flag );

log_entry ( "### Phase II - cleaning temporary files and directories in $base_2", $debug_flag+$verbose_flag );

open ( LOG, "xdeltadir.log" ) || die ( "Error: can not open file xdeltadir.log for reading" );

clean_temp ( 0 );

seek ( LOG, 0, 0 );

clean_temp ( 1 );

close ( LOG );

log_entry ( "Temporary files removed.", $debug_flag+$verbose_flag );
