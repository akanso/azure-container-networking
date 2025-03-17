    numDeployments=1000
    depKind="real-nginx"

    for num in $(seq 1 $numDeployments); do
        i="`printf "%05g" $num`"
        echo $i
	name="$depKind-dep-$i"
        labelPrefix="$depKind-dep-lab-$i"
        outFile=generated/deployments/$depKind/$name.yaml

        sed "s/TEMP_NAME/$name/g" templates/$depKind-deployment.yaml > $outFile
        sed -i "s/TEMP_REPLICAS/25/g" $outFile

        if [[ 5 -gt 0 ]]; then
            depLabels=""
            for j in $(seq -f "%05g" 1 5); do
                depLabels="$depLabels\n      $labelPrefix-$j: val"
            done
            perl -pi -e "s/OTHER_LABELS_6_SPACES/$depLabels/g" $outFile

            depLabels=""
            for j in $(seq -f "%05g" 1 5); do
                depLabels="$depLabels\n        $labelPrefix-$j: val"
            done
            perl -pi -e "s/OTHER_LABELS_8_SPACES/$depLabels/g" $outFile

            # Relies on # of CNP = # of Deployment.

            # Only create CNP for 25% of Deployment. = 0.25 * 1000 * 100 = 25000 pods
            if [[ $num -le 250 ]]; then
                fileName=generated/ciliumnetworkpolicies/applied/policy-$i.yaml
                sed "s/TEMP_NAME/policy-$i/g" templates/ciliumnetworkpolicy.yaml > $fileName
                cnpLabel="$labelPrefix-00001"
                sed -i "s/TEMP_LABEL_NAME/$cnpLabel/g" $fileName
            fi

        else
            sed -i "s/OTHER_LABELS_6_SPACES//g" $outFile
            sed -i "s/OTHER_LABELS_8_SPACES//g" $outFile
        fi
    done
