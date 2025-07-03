PREFIX=${HOME}/.local

.PHONY: all install clean wipe

all: SISSO

SISSO: src/var_global.f90 src/libsisso.f90 src/DI.f90 src/FC.f90 src/FCse.f90 src/SISSO.f90
	mpif90 $^ -o $@

install: SISSO
	install SISSO ${PREFIX}/bin

clean:
	rm -f *.mod

wipe: clean
	rm SISSO
