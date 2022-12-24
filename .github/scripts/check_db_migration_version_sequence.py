import os
import sys
def check_flyway_sequence(db_dir):
    for (root,dirs,files) in os.walk(db_dir, topdown=True):
        print("List of flyway version files:")
        print(', '.join(files))
        versions = []
        for file in files:
            ver = file.split('__')[0][1:]
            if int(ver) in versions:
                raise Exception(f"The flyway version files must be in sequence and cannot be duplicate. The {ver} already exists.")
            else:
                versions.append(int(ver))
        versions.sort()
        for index, ver in enumerate(versions):
            if index + 1 != ver:
                raise Exception(f"The flyway version files must be in sequence. Missing V{index + 1} file, instead found V{ver} file.")

if __name__ == '__main__':
  check_flyway_sequence(sys.argv[1])
